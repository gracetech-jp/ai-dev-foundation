#!/usr/bin/env bats
# audit-consistency.sh 検査層(6)「配布複製の同期検査（root ↔ profiles/_base）」の回帰。
# 実リポの working tree を汚さないため、監査対象一式をサンドボックスへ複製してから破壊する。

setup() {
	REPO="$BATS_TEST_DIRNAME/.."
}

# 監査スクリプトが参照する一式を複製する（.claude はローカル設定 settings.local.json を含めない）
make_sandbox() {
	SB="$BATS_TEST_TMPDIR/sb"
	mkdir -p "$SB/.claude" "$SB/docs"
	for item in Makefile CLAUDE.md .backport-manifest \
	            .req-coverage-baseline scripts profiles .github .devcontainer; do
		cp -a "$REPO/$item" "$SB/$item"
	done
	cp -a "$REPO/docs/rules" "$REPO/docs/requirements" "$REPO/docs/service-rules" "$REPO/docs/decisions" "$SB/docs/"
	cp "$REPO/.claude/settings.json" "$SB/.claude/"
	cp -a "$REPO/.claude/scripts" "$REPO/.claude/skills" "$REPO/.claude/agents" "$SB/.claude/"
}

audit() { (cd "$SB" && bash scripts/audit-consistency.sh); }

# ---- 緑 ----

@test "緑: サンドボックス（現リポの複製）で監査が通る" {
	make_sandbox
	run audit
	[ "$status" -eq 0 ]
}

@test "緑: settings.json は permissions が同値なら root 固有キー（model等）の差を許容する" {
	make_sandbox
	# root 側にのみ存在するローカル固有キーを追加しても層(6)は赤にならない
	jq '. + {theme: "light", model: "dummy"}' "$SB/.claude/settings.json" > "$SB/.claude/settings.json.tmp"
	mv "$SB/.claude/settings.json.tmp" "$SB/.claude/settings.json"
	run audit
	[ "$status" -eq 0 ]
}

# ---- 赤 ----

@test "赤: profiles/_base 側の guard-dangerous.sh だけ改変すると不一致で fail" {
	make_sandbox
	echo "# drift" >> "$SB/profiles/_base/.claude/scripts/guard-dangerous.sh"
	run audit
	[ "$status" -eq 1 ]
	[[ "$output" == *"配布複製が不一致"*"guard-dangerous.sh"* ]]
}

@test "赤: root 側のスキルファイルだけ削除すると片側欠落で fail" {
	make_sandbox
	rm "$SB/.claude/skills/verify-request/SKILL.md"
	run audit
	[ "$status" -eq 1 ]
	[[ "$output" == *"配布複製の片側欠落"*"verify-request/SKILL.md"* ]]
}

@test "赤: profiles/_base 側にだけ新規エージェントを置くと片側欠落で fail" {
	make_sandbox
	mkdir -p "$SB/profiles/_base/.claude/agents"
	echo "dummy" > "$SB/profiles/_base/.claude/agents/only-base.md"
	run audit
	[ "$status" -eq 1 ]
	[[ "$output" == *"配布複製の片側欠落"*"only-base.md"*"root 側に無い"* ]]
}

@test "赤: _base 側 settings.json の permissions.deny を1件消すと fail" {
	make_sandbox
	jq '.permissions.deny -= ["Bash(git push:*)"]' "$SB/profiles/_base/.claude/settings.json" \
		> "$SB/profiles/_base/.claude/settings.json.tmp"
	mv "$SB/profiles/_base/.claude/settings.json.tmp" "$SB/profiles/_base/.claude/settings.json"
	run audit
	[ "$status" -eq 1 ]
	[[ "$output" == *"permissions が root ↔ profiles/_base で不一致"* ]]
}

# ---- 検査層(7): 共通所有ロックの定義突合（2026-07-25 追加） ----

@test "赤: guard の COMMON_OWNED に無いパスを deny に足すと乖離で fail" {
	make_sandbox
	jq '.permissions.deny += ["Write(docs/newthing.md)", "Edit(docs/newthing.md)"]' \
		"$SB/profiles/_base/.claude/settings.json" > "$SB/t.json"
	mv "$SB/t.json" "$SB/profiles/_base/.claude/settings.json"
	run audit
	[ "$status" -eq 1 ]
	[[ "$output" == *"共通所有ロックの乖離"*"docs/newthing.md"*"COMMON_OWNED に掛かりません"* ]]
}

@test "赤: deny の Write/Edit が非対称になると fail" {
	make_sandbox
	jq '.permissions.deny |= map(select(. != "Edit(CLAUDE.md)"))' \
		"$SB/profiles/_base/.claude/settings.json" > "$SB/t.json"
	mv "$SB/t.json" "$SB/profiles/_base/.claude/settings.json"
	run audit
	[ "$status" -eq 1 ]
	[[ "$output" == *"Write/Edit が非対称"* ]]
}

@test "赤: manifest の配布対象がロックされていないと fail" {
	make_sandbox
	echo "scripts/unlocked-thing.sh" >> "$SB/.backport-manifest"
	run audit
	[ "$status" -eq 1 ]
	[[ "$output" == *"共通所有ロックの乖離"*"scripts/unlocked-thing.sh"*"配布 deny にありません"* ]]
}

@test "赤: ロックのコア1件を deny から外すと退化検出で fail（旧 length>0 では素通りしていた）" {
	make_sandbox
	jq '.permissions.deny |= map(select(. != "Write(scripts/sync-from-common.sh)" and . != "Edit(scripts/sync-from-common.sh)"))' \
		"$SB/profiles/_base/.claude/settings.json" > "$SB/t.json"
	mv "$SB/t.json" "$SB/profiles/_base/.claude/settings.json"
	run audit
	[ "$status" -eq 1 ]
	[[ "$output" == *"ロックの退化"*"scripts/sync-from-common.sh"* ]]
}

# ---- 検査層(8): 基盤自身のゲート無効化検出（2026-07-25 追加） ----

@test "赤: 基盤の tier-tripwire を空設定に戻すと無効化検出で fail" {
	make_sandbox
	sed -i "s|@TIER_TRIPWIRE_PATHS='[^']*'|@TIER_TRIPWIRE_PATHS=\"\"|" "$SB/Makefile"
	run audit
	[ "$status" -eq 1 ]
	[[ "$output" == *"TIER_TRIPWIRE_PATHS 空で起動"* ]]
}

@test "赤: 基盤に .tier-tripwire-none を置くと無効化検出で fail" {
	make_sandbox
	: > "$SB/docs/requirements/.tier-tripwire-none"
	run audit
	[ "$status" -eq 1 ]
	[[ "$output" == *".tier-tripwire-none があります"* ]]
}
