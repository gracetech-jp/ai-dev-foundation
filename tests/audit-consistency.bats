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
	# common / templates / マーカーは検査層(10)（参照方式への移行中の複製同期検査）の対象。
	# 複製し忘れると層(10)がサンドボックスで必ず落ちる（2026-07-26 フェーズ0で追加）。
	for item in Makefile CLAUDE.md \
	            .req-coverage-baseline scripts profiles .github .devcontainer \
	            common service-templates .ai-dev-foundation-root; do
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

# Write(path) はファイル権限チェックに一致せず効かない。Edit(path) が全ファイル編集ツールを覆う。
# 旧テストは Write/Edit の対称性を要求していたが、効かないルールを必須にする検査だった（2026-07-26 是正）。
@test "赤: 効かない Write(...) の deny を配布 settings.json に置くと fail" {
	make_sandbox
	jq '.permissions.deny += ["Write(CLAUDE.md)"]' \
		"$SB/profiles/_base/.claude/settings.json" > "$SB/t.json"
	mv "$SB/t.json" "$SB/profiles/_base/.claude/settings.json"
	run audit
	[ "$status" -eq 1 ]
	[[ "$output" == *"Write(...) の deny が残っています"* ]]
}

@test "赤: ロックのコアから Edit を1件外すと退化検出で fail" {
	make_sandbox
	jq '.permissions.deny |= map(select(. != "Edit(CLAUDE.md)"))' \
		"$SB/profiles/_base/.claude/settings.json" > "$SB/t.json"
	mv "$SB/t.json" "$SB/profiles/_base/.claude/settings.json"
	run audit
	[ "$status" -eq 1 ]
	# 部分文字列ごとに検査する（1つの glob で順に並べると、別の検査が出す
	# 「CLAUDE.md」を含む行に引っ張られて**別の理由で緑になる**ため。2026-07-30）
	[[ "$output" == *"ロックの退化"* ]]
	[[ "$output" == *"Edit(CLAUDE.md)"* ]]
}

# 旧「manifest の配布対象がロックされていないと fail」は 2026-07-30 に撤去した
# （順輸入廃止・ADR-010 でマニフェストが無くなり、検査ごと消えたため）。

@test "赤: ロックのコア1件を deny から外すと退化検出で fail（旧 length>0 では素通りしていた）" {
	make_sandbox
	jq '.permissions.deny |= map(select(. != "Edit(.claude/scripts/session-start-rules.sh)"))' \
		"$SB/profiles/_base/.claude/settings.json" > "$SB/t.json"
	mv "$SB/t.json" "$SB/profiles/_base/.claude/settings.json"
	run audit
	[ "$status" -eq 1 ]
	[[ "$output" == *"ロックの退化"* ]]
	[[ "$output" == *"Edit(.claude/scripts/session-start-rules.sh)"* ]]
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

@test "赤: CI から tier-tripwire ジョブが消えると退化検出で fail" {
	make_sandbox
	sed -i '/^  tier-tripwire:$/,+7d' "$SB/.github/workflows/ci.yml"
	run audit
	[ "$status" -eq 1 ]
	[[ "$output" == *"必須ジョブ 'tier-tripwire' がありません"* ]]
}

# ---- 赤: 検査層(10) 参照方式への移行中の複製同期（2026-07-26 フェーズ0） ----
# 移行期は正本(common/ ・ service-templates/)と旧パスの実体が併存する。片方だけ育つ乖離を機械で止める。

@test "赤: _base の Dockerfile だけ改変すると複製の不一致で fail" {
	make_sandbox
	echo "# drift" >> "$SB/profiles/_base/.devcontainer/Dockerfile"
	run audit
	[ "$status" -eq 1 ]
	[[ "$output" == *"移行複製が不一致"* ]]
	[[ "$output" == *"Dockerfile"* ]]
}

@test "赤: composite action 同梱スクリプトだけ改変すると移行複製の不一致で fail" {
	make_sandbox
	echo "# drift" >> "$SB/.github/actions/tier-tripwire/check-tier-tripwire.sh"
	run audit
	[ "$status" -eq 1 ]
	[[ "$output" == *"移行複製が不一致"* ]]
}

@test "赤: templates 側だけ改変すると profiles/_base との不一致で fail" {
	make_sandbox
	echo "# drift" >> "$SB/service-templates/scripts/audit-consistency.sh"
	run audit
	[ "$status" -eq 1 ]
	[[ "$output" == *"移行複製が不一致"*"service-templates/"* ]]
}

@test "赤: マーカーを消すと参照方式の起点欠落で fail" {
	make_sandbox
	rm "$SB/.ai-dev-foundation-root"
	run audit
	[ "$status" -eq 1 ]
	[[ "$output" == *"マーカー"* ]]
}
