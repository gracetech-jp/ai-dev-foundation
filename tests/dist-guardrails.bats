#!/usr/bin/env bats
# 配布側（生成プロジェクト）の監査 検査(5)「ガードレール二重化の突合」の回帰。
#
# なぜテストで固定するか: 基盤リポの検査(14)は基盤だけを守る。生成プロジェクト側で deny が
# 片側だけ消えても、そこに検査が無ければ誰も気づけない——**基盤だけ守られて配布先が守られない**
# 状態になる（ADR-012 の目的に反する）。配布された検査が実際に動くことをここで担保する。
#
# 実際に new-service.sh で生成した成果物に対して監査を走らせる（雛形を直接読むのではなく、
# 配布経路を通ったものを検証する。配布行の抜けもここで落ちる）。
#
# @req: R-001
# @adversarial: R-001

setup() {
	REPO="$BATS_TEST_DIRNAME/.."
	export HOME="$BATS_TEST_TMPDIR/home"
	mkdir -p "$HOME"
	# 生成先は「共通基盤の projects/ 配下」固定。基盤の最小複製を作ってそこから生成する。
	# .claude/scripts も複製する: 検査(5)はマーカーを上方探索して**共通側のフック**と突合するため、
	# これが無いと「第3層が配られていない」で赤になる（それ自体は正しい挙動）。
	FSB="$BATS_TEST_TMPDIR/foundation"
	mkdir -p "$FSB/scripts" "$FSB/.claude"
	cp "$REPO/scripts/new-service.sh" "$FSB/scripts/"
	cp -a "$REPO/profiles" "$FSB/profiles"
	cp -a "$REPO/common" "$FSB/common"
	cp -a "$REPO/.claude/scripts" "$FSB/.claude/scripts"
	cp "$REPO/.ai-dev-foundation-root" "$FSB/"
	PROJ="$FSB/projects/svc"
	bash "$FSB/scripts/new-service.sh" svc --profile product-static >/dev/null
}

dist_audit() { (cd "$PROJ" && bash scripts/audit-consistency.sh); }

# 生成物の settings.json から deny を1件落とす
drop_deny() { # <ルール文字列>
	jq --arg r "$1" '.permissions.deny -= [$r]' "$PROJ/.claude/settings.json" > "$PROJ/t.json"
	mv "$PROJ/t.json" "$PROJ/.claude/settings.json"
}

# ---- 緑 ----

@test "緑: 生成直後のプロジェクトで検査(5)が通る" {
	run dist_audit
	[ "$status" -eq 0 ]
}

@test "緑: チェックリストが配布されている（第2層の実測手順）" {
	[ -f "$PROJ/scripts/verify-guardrails.md" ]
	# 層を切り分ける項目7 を含むこと（これが無いと第2層の生死を確認できない）
	grep -q 'ls -la .env' "$PROJ/scripts/verify-guardrails.md"
}

# ---- 赤: 第2層の退化 ----

@test "赤: 二重化した deny を1件落とすと fail する" {
	drop_deny "Bash(git reset *--hard*)"
	run dist_audit
	[ "$status" -eq 1 ]
	[[ "$output" == *"二重化の退化"*"A3"* ]]
}

@test "赤: deny コアを落とすと fail する" {
	drop_deny "Read(**/.env)"
	run dist_audit
	[ "$status" -eq 1 ]
	[[ "$output" == *"deny コアの退化"* ]]
}

@test "赤: settings.json ごと消えると fail する" {
	rm "$PROJ/.claude/settings.json"
	run dist_audit
	[ "$status" -eq 1 ]
	[[ "$output" == *"第2層の実体"* ]]
}

# ---- 赤: 第3層・配布経路の退化 ----

@test "赤: プロジェクト側にフック定義を書き戻すと fail する" {
	jq '. + {hooks:{PreToolUse:[{matcher:"Bash",hooks:[{type:"command",command:"bash \"$CLAUDE_PROJECT_DIR/.claude/scripts/guard-dangerous.sh\""}]}]}}' \
		"$PROJ/.claude/settings.json" > "$PROJ/t.json"
	mv "$PROJ/t.json" "$PROJ/.claude/settings.json"
	run dist_audit
	[ "$status" -eq 1 ]
	[[ "$output" == *"フック定義があります"* ]]
}

@test "赤: プロジェクト側にフック複製が生えると fail する" {
	mkdir -p "$PROJ/.claude/scripts"
	echo '#!/usr/bin/env bash' > "$PROJ/.claude/scripts/guard-dangerous.sh"
	run dist_audit
	[ "$status" -eq 1 ]
	[[ "$output" == *"フック複製があります"* ]]
}

@test "赤: 共通 .claude のマウントが消えると fail する" {
	grep -v '/home/node/.claude' "$PROJ/.devcontainer/devcontainer.json" > "$PROJ/d.json"
	mv "$PROJ/d.json" "$PROJ/.devcontainer/devcontainer.json"
	run dist_audit
	[ "$status" -eq 1 ]
	[[ "$output" == *"マウントしていません"* ]]
}

@test "赤: 共通側のフックから判定マーカーが消えると fail する" {
	grep -v '@dual-layer: A6' "$FSB/.claude/scripts/guard-dangerous.sh" > "$FSB/g.sh"
	mv "$FSB/g.sh" "$FSB/.claude/scripts/guard-dangerous.sh"
	run dist_audit
	[ "$status" -eq 1 ]
	[[ "$output" == *"フックに判定 A6 のマーカーがありません"* ]]
}

@test "赤: 共通側のフック本体が読めないと fail する（配られていない状態）" {
	rm "$FSB/.claude/scripts/guard-dangerous.sh"
	run dist_audit
	[ "$status" -eq 1 ]
	[[ "$output" == *"第3層が配られていません"* ]]
}

# ---- スキップの可視化 ----

@test "緑: 共通基盤が見つからない場合は、黙って飛ばさずスキップを明示する" {
	# CI の単独チェックアウト相当（マーカーが上方に無い）。**黙って飛ばさない**ことを固定する。
	#
	# 【2026-08-08 に挙動が変わった】以前はこの状況でも第2層（deny の実在）だけは検証していた。
	# 判定が雛形にインライン複製されていたからである。共通側へ抽出した結果、共通基盤が
	# 解決できない状況では**共通監査そのものが走らない**——スクリプトが共通側にあるため。
	# 検査 6〜9 は元からこの挙動で、抽出によって5も揃った形になる。
	# 通常の CI では問題にならない: 雛形の ci.yml は reusable workflow を使い、
	# それが共通基盤を `path: .` へ checkout する。ここに来るのは単独チェックアウトのときだけ。
	rm "$FSB/.ai-dev-foundation-root"
	run dist_audit
	[ "$status" -eq 0 ]
	[[ "$output" == *"共通監査はスキップしました"* ]]
}
