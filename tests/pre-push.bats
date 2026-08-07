#!/usr/bin/env bats
# common/scripts/pre-push（push 前ゲート）の回帰。
#
# **共通の pre-push は全リポジトリが共有する。** ここが止まると、この基盤と無関係な理由で
# 各サービスの push が止まる。したがって固定したいのは2方向ある。
#   1. 止めるべきものを止める（lint の本物の違反で push がブロックされること）
#   2. **止めるべきでないもので止めない**（lint 未実装・ターゲット未定義のリポジトリが push できること）
# 2 は静かに壊れる——基盤側で lint を足した瞬間に、lint を持たないリポジトリが push できなくなる。
#
# 【なぜ lint が先頭か】
# shellcheck 系は秒で終わり、下の4段は分単位かかる。単純な指摘ほど早く返す。
# 2026-08-07 に「push して数分後に SC2015 の info 1件で CI が赤」を実際に踏んだのが追加の契機。
#
# 各ケースは「全ゲートが通る Makefile を作ってから1箇所だけ壊す」（変異注入）。

SUT="${BATS_TEST_DIRNAME}/../common/scripts/pre-push"

setup() {
	P="$BATS_TEST_TMPDIR/proj"
	mkdir -p "$P"
	git -C "$P" init -q
	# pre-push は `git rev-parse --show-toplevel` で対象を決めるため、リポジトリの中で実行する。
	# レシピ行は TAB 必須なので printf で書く（ヒアドキュメントは TAB を剥がす）。
	all_green_makefile
}

# 4段 + lint がすべて通る Makefile。除外したいターゲット名を引数で渡すとそれだけ書かない
# （行単位で削るのではなく最初から書かない——レシピ行だけ残ると Makefile 自体が壊れ、
#   「未定義だから soft」ではなく「構文エラーで red」を測ってしまう）。
all_green_makefile() {
	local skip="${1:-}" t
	: > "$P/Makefile"
	for t in lint audit-all test req-coverage tier-tripwire; do
		[ "$t" = "$skip" ] && continue
		printf '%s:\n\t@echo "[%s] ok"\n' "$t" "$t" >> "$P/Makefile"
	done
}

run_hook() { run bash -c "cd '$P' && bash '$SUT'"; }

# ---- 緑 ----

@test "緑: 全ゲートが通れば push はブロックされない" {
	run_hook
	[ "$status" -eq 0 ]
	[[ "$output" == *"lint 通過"* ]]
}

@test "緑: lint は4段より先に走る（速いものを先に返す）" {
	run_hook
	[ "$status" -eq 0 ]
	lint_line="$(printf '%s\n' "$output" | grep -n 'lint（静的解析）' | cut -d: -f1)"
	audit_line="$(printf '%s\n' "$output" | grep -n '整合性監査' | head -1 | cut -d: -f1)"
	[ "$lint_line" -lt "$audit_line" ]
}

# ---- 緑: 止めるべきでないもので止めない（共有資産としての要）----

@test "緑: lint ターゲットが未定義のリポジトリでも push できる" {
	all_green_makefile lint
	! grep -q '^lint:' "$P/Makefile"      # 前提の確認（変異が効いていること）
	run_hook
	[ "$status" -eq 0 ]
	[[ "$output" == *"定義されていない"* ]]
}

@test "緑: lint が未実装（TODO=exit 3）でも push できる" {
	all_green_makefile lint
	printf 'lint:\n\t@echo "[lint] TODO"\n\t@exit 3\n' >> "$P/Makefile"
	run_hook
	[ "$status" -eq 0 ]
	[[ "$output" == *"TODO"* ]]
}

# ---- 赤: 止めるべきものは止める ----

@test "赤: lint が本物の違反で落ちたら push をブロックする" {
	all_green_makefile lint
	printf 'lint:\n\t@echo "SC2015 の警告"; exit 1\n' >> "$P/Makefile"
	run_hook
	[ "$status" -eq 1 ]
	[[ "$output" == *"lint が失敗しました"* ]]
}

@test "赤: lint が落ちたら4段は走らせない（無駄に数分待たせない）" {
	all_green_makefile lint
	printf 'lint:\n\t@echo "警告"; exit 1\n' >> "$P/Makefile"
	run_hook
	[ "$status" -eq 1 ]
	[[ "$output" != *"整合性監査"* ]]
}

@test "赤: 従来の4段も引き続きブロックする（audit-all）" {
	all_green_makefile audit-all
	printf 'audit-all:\n\t@echo "不整合"; exit 1\n' >> "$P/Makefile"
	run_hook
	[ "$status" -eq 1 ]
	[[ "$output" == *"整合性監査が失敗"* ]]
}

@test "赤: 従来の4段も引き続きブロックする（test）" {
	all_green_makefile test
	printf 'test:\n\t@echo "失敗"; exit 1\n' >> "$P/Makefile"
	run_hook
	[ "$status" -eq 1 ]
	[[ "$output" == *"単体テストが失敗"* ]]
}
