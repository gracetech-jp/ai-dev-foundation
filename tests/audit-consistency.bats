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
