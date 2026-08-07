#!/usr/bin/env bats
# common/scripts/run-gates.sh（品質ゲートの soft/hard 判定）の回帰。
#
# この判定は 2026-07-23 から CI の YAML に直書きされており、**一度もテストされていなかった**。
# ADR-011 でスクリプトへ実体化したのに伴い、挙動を固定資産にする。
# 特に固定したいのは次の3点——どれも「静かに壊れる」типの失敗をする。
#   1. softable の soft 化は **TODO 契約（exit 3）のときだけ**（本物の違反まで soft になると気づけない）
#   2. hard が失敗しても**後続のゲートは実行される**（1回で全部の結果が出ないと直すのに何往復もかかる）
#   3. coverage は .coverage-floor が 0 か否かで soft/hard が**自動で**切り替わる（人手の設定変更を要さない）

SUT="${BATS_TEST_DIRNAME}/../common/scripts/run-gates.sh"

setup() {
	P="$BATS_TEST_TMPDIR/proj"
	mkdir -p "$P"
}

# テスト用の Makefile を書く。TODO ターゲットは契約どおり exit 3 を返す。
# printf で書くのは、ヒアドキュメント（<<-）が**レシピ行の TAB を剥いで Makefile を壊す**ため
# （実際にこれで最初のテストが落ちた。Makefile のレシピは TAB 必須）。
make_project() {
	printf 'ok:\n\t@echo "ok done"\n' > "$P/Makefile"
	printf 'todo:\n\t@exit 3\n' >> "$P/Makefile"
	printf 'broken:\n\t@echo "本物の違反"; exit 1\n' >> "$P/Makefile"
	printf 'cov:\n\t@echo "coverage 実行"; exit 1\n' >> "$P/Makefile"
}

# ---- 正常系 ----

@test "緑: 全ターゲットが成功すれば exit 0" {
	make_project
	run bash "$SUT" "$P" hard:ok softable:ok
	[ "$status" -eq 0 ]
	[[ "$output" == *"全ゲート通過"* ]]
}

# ---- softable の判定 ----

@test "緑: softable + TODO(exit 3) は warning に落として続行する" {
	make_project
	run bash "$SUT" "$P" softable:todo
	[ "$status" -eq 0 ]
	[[ "$output" == *"::warning::"* ]]
	[[ "$output" == *"未実装(TODO=exit 3)"* ]]
}

@test "赤: softable でも TODO 以外の失敗は red（本物の違反を soft にしない）" {
	make_project
	run bash "$SUT" "$P" softable:broken
	[ "$status" -eq 1 ]
	[[ "$output" == *"broken 失敗（red）"* ]]
}

@test "赤: hard は TODO(exit 3)でも red（要件トレーサビリティは fail-closed）" {
	make_project
	run bash "$SUT" "$P" hard:todo
	[ "$status" -eq 1 ]
	[[ "$output" == *"todo 失敗（red）"* ]]
}

# ---- 失敗しても続行する ----

@test "赤: 先頭が失敗しても後続のゲートは実行される（1回で全結果が出る）" {
	make_project
	run bash "$SUT" "$P" hard:broken hard:ok
	[ "$status" -eq 1 ]
	[[ "$output" == *"broken 失敗（red）"* ]]
	[[ "$output" == *"✅ ok"* ]]
}

# ---- coverage の floor による自動切替 ----

@test "緑: auto は .coverage-floor=0 の間 soft（ラチェットが何も守っていないため）" {
	make_project
	echo "0" > "$P/.coverage-floor"
	run bash "$SUT" "$P" auto:cov
	[ "$status" -eq 0 ]
	[[ "$output" == *"floor=0"* ]]
}

@test "赤: auto は .coverage-floor>0 になった時点で自動的に hard 化する" {
	make_project
	echo "80" > "$P/.coverage-floor"
	run bash "$SUT" "$P" auto:cov
	[ "$status" -eq 1 ]
	[[ "$output" == *"cov 失敗（red）"* ]]
}

@test "緑: .coverage-floor が無ければ 0 とみなす（生成直後の状態）" {
	make_project
	run bash "$SUT" "$P" auto:cov
	[ "$status" -eq 0 ]
}

# ---- 呼び出し方の誤りは fail-closed ----

# ---- optional（pre-push 専用。フックは便宜であって権威ではない） ----

@test "緑: optional はターゲット未定義でも soft（lint 未実装のリポジトリで push を止めない）" {
	make_project      # lint ターゲットは書いていない
	run bash "$SUT" "$P" optional:lint
	[ "$status" -eq 0 ]
	[[ "$output" == *"定義されていない"* ]]
}

@test "赤: softable はターゲット未定義なら red のまま（CI の fail-closed 契約を変えない）" {
	# optional と softable の違いはここだけ。CI 側の契約まで緩めていないことを固定する。
	make_project
	run bash "$SUT" "$P" softable:lint
	[ "$status" -eq 1 ]
}

@test "緑: optional は TODO(exit 3) も soft（softable と同じ扱い）" {
	make_project
	run bash "$SUT" "$P" optional:todo
	[ "$status" -eq 0 ]
	[[ "$output" == *"TODO"* ]]
}

@test "赤: optional でも本物の違反は red（未定義でも TODO でもない失敗は通さない）" {
	make_project
	run bash "$SUT" "$P" optional:broken
	[ "$status" -eq 1 ]
	[[ "$output" == *"本物の違反"* ]]
}

@test "exit 2: 引数不足は fail-closed" {
	run bash "$SUT" "$P"
	[ "$status" -eq 2 ]
}

@test "exit 2: 存在しないプロジェクトルートは fail-closed" {
	run bash "$SUT" "$BATS_TEST_TMPDIR/nope" hard:ok
	[ "$status" -eq 2 ]
}

@test "exit 2: mode 無しの指定は fail-closed（黙って hard 扱いにしない）" {
	make_project
	run bash "$SUT" "$P" lint
	[ "$status" -eq 2 ]
	[[ "$output" == *"<mode>:<target>"* ]]
}

@test "exit 2: 未知の mode は fail-closed" {
	make_project
	run bash "$SUT" "$P" maybe:ok
	[ "$status" -eq 2 ]
	[[ "$output" == *"不正な mode"* ]]
}
