#!/usr/bin/env bats
# common/scripts/check-required-checks.sh（必須ステータスチェック宣言の検査）の回帰。
#
# この検査が守るのは「ブランチ保護の必須チェックが、実際に PR で報告されるジョブを指していること」。
# 外れ方が2種類あり、**片方は静かに壊れる**ので両方を固定する。
#   - 宣言が実在しない／PR で走らないジョブを指す → PR が永久にブロックされる（fail-closed・気づける）
#   - PR では走らないゲートを必須のつもりで並べる → 緑に見えて何も守らない（fail-open・気づけない）
# 後者は 2026-08-06 に既存プロジェクト（deploy.yml が push: main のみ）で実際に見つかった形である。
#
# 各ケースは「正常な構成を作ってから1箇所だけ壊す」（変異注入）。
# 壊す前が緑であることを毎回踏むので、検査が空撃ちになっていないことも同時に確認できる。

SUT="${BATS_TEST_DIRNAME}/../common/scripts/check-required-checks.sh"

setup() {
	P="$BATS_TEST_TMPDIR/proj"
	mkdir -p "$P/.github/workflows"
}

# push / pull_request で走る正常なワークフロー1本と、それに一致する宣言。
make_ok_project() {
	printf 'name: CI\non:\n  push:\n  pull_request:\n\njobs:\n  audit:\n    runs-on: ubuntu-latest\n    steps:\n      - run: make audit-all\n  test:\n    runs-on: ubuntu-latest\n    steps:\n      - run: make test\n' > "$P/.github/workflows/ci.yml"
	printf '# 宣言\naudit\ntest\n' > "$P/.github/required-checks.txt"
}

run_sut() { run bash "$SUT" "$P"; }

# ---- 緑 ----

@test "緑: 宣言が実在し pull_request で走り重複が無ければ通る" {
	make_ok_project
	run_sut
	[ "$status" -eq 0 ]
}

@test "緑: コメント行・空行・前後の空白は無視される" {
	make_ok_project
	printf '# コメント\n\n   audit   \ntest\n\n' > "$P/.github/required-checks.txt"
	run_sut
	[ "$status" -eq 0 ]
}

@test "緑: on: が配列形（[push, pull_request]）でも pull_request を認識する" {
	make_ok_project
	printf 'name: CI\non: [push, pull_request]\n\njobs:\n  audit:\n    runs-on: ubuntu-latest\n    steps:\n      - run: true\n' > "$P/.github/workflows/ci.yml"
	printf 'audit\n' > "$P/.github/required-checks.txt"
	run_sut
	[ "$status" -eq 0 ]
}

@test "緑: workflow_call 専用のジョブ名は素の名前空間と衝突しない（接頭辞が付くため）" {
	make_ok_project
	# 呼ばれる側に、素の CI と同じ 'audit' というジョブがあっても衝突ではない。
	# 呼ばれると `<呼び出し側のジョブ id> / audit` になるため。
	printf 'name: reusable\non:\n  workflow_call:\n\njobs:\n  audit:\n    runs-on: ubuntu-latest\n    steps:\n      - run: true\n' > "$P/.github/workflows/reusable.yml"
	run_sut
	[ "$status" -eq 0 ]
}

@test "緑: reusable 呼び出し形（'ci / gates'）は接頭辞のジョブだけを検証する" {
	printf 'name: CI\non:\n  push:\n  pull_request:\n\njobs:\n  ci:\n    uses: org/repo/.github/workflows/service-ci.yml@v1\n' > "$P/.github/workflows/ci.yml"
	printf 'ci / gates\n' > "$P/.github/required-checks.txt"
	run_sut
	[ "$status" -eq 0 ]
	[[ "$output" == *"接頭辞のみ検証"* ]]
}

@test "緑: ワークフローも宣言も無いリポジトリはスキップする（CI そのものが無い）" {
	rmdir "$P/.github/workflows"
	run_sut
	[ "$status" -eq 0 ]
	[[ "$output" == *"スキップ"* ]]
}

# ---- 赤: ① 実在しない ----

@test "赤: 宣言した名前のジョブが存在しないと fail する" {
	make_ok_project
	printf 'audit\nlint\n' > "$P/.github/required-checks.txt"   # lint は定義していない
	run_sut
	[ "$status" -eq 1 ]
	[[ "$output" == *"'lint' がワークフローにありません"* ]]
}

@test "赤: ジョブ名を変えて宣言を直し忘れると fail する（改名の追随漏れ）" {
	make_ok_project
	sed -i 's/^  audit:/  audit-all:/' "$P/.github/workflows/ci.yml"
	run_sut
	[ "$status" -eq 1 ]
	[[ "$output" == *"'audit' がワークフローにありません"* ]]
}

# ---- 赤: ② pull_request で走らない ----

@test "赤: push でしか走らないワークフローのジョブを宣言すると fail する" {
	# 2026-08-06 に実在プロジェクトで見つかった形。テストが PR で走らないのに
	# 必須チェックのつもりで並べると、緑に見えて何も守らない。
	make_ok_project
	printf 'name: Deploy\non:\n  push:\n    branches: [main]\n\njobs:\n  test-backend:\n    runs-on: ubuntu-latest\n    steps:\n      - run: pytest\n' > "$P/.github/workflows/deploy.yml"
	printf 'audit\ntest\ntest-backend\n' > "$P/.github/required-checks.txt"
	run_sut
	[ "$status" -eq 1 ]
	[[ "$output" == *"pull_request で走りません"* ]]
}

@test "赤: workflow_dispatch 限定のジョブを宣言すると fail する（selftest を必須にした場合）" {
	make_ok_project
	printf 'name: selftest\non:\n  workflow_dispatch:\n\njobs:\n  selftest:\n    uses: org/repo/.github/workflows/service-ci.yml@main\n' > "$P/.github/workflows/selftest.yml"
	printf 'audit\nselftest / gates\n' > "$P/.github/required-checks.txt"
	run_sut
	[ "$status" -eq 1 ]
	[[ "$output" == *"pull_request で走りません"* ]]
}

@test "赤: pull_request_target を pull_request と誤認しない" {
	make_ok_project
	printf 'name: PRT\non:\n  pull_request_target:\n\njobs:\n  labeler:\n    runs-on: ubuntu-latest\n    steps:\n      - run: true\n' > "$P/.github/workflows/prt.yml"
	printf 'labeler\n' > "$P/.github/required-checks.txt"
	run_sut
	[ "$status" -eq 1 ]
	[[ "$output" == *"pull_request で走りません"* ]]
}

# ---- 赤: ③ ジョブ名の重複 ----

@test "赤: 複数のワークフローに同名ジョブがあると fail する" {
	make_ok_project
	printf 'name: Nightly\non:\n  pull_request:\n\njobs:\n  test:\n    runs-on: ubuntu-latest\n    steps:\n      - run: true\n' > "$P/.github/workflows/nightly.yml"
	run_sut
	[ "$status" -eq 1 ]
	[[ "$output" == *"複数のワークフローで定義されています"* ]]
}

@test "赤: job-level の name: が別ジョブの id と衝突しても検出する" {
	# チェック名は name: があればそちらになる。id だけ見ていると素通りする穴。
	make_ok_project
	printf 'name: Extra\non:\n  pull_request:\n\njobs:\n  something:\n    name: audit\n    runs-on: ubuntu-latest\n    steps:\n      - run: true\n' > "$P/.github/workflows/extra.yml"
	run_sut
	[ "$status" -eq 1 ]
	[[ "$output" == *"'audit' が複数のワークフローで定義されています"* ]]
}

@test "緑: ステップの name は job-level の name と混同されない" {
	make_ok_project
	printf 'name: Steps\non:\n  pull_request:\n\njobs:\n  build:\n    runs-on: ubuntu-latest\n    steps:\n      - name: audit\n        run: true\n' > "$P/.github/workflows/steps.yml"
	run_sut
	[ "$status" -eq 0 ]
}

# ---- 赤: 宣言そのものの欠落 ----

@test "赤: 宣言ファイルが無いと fail する（何を必須にすべきかが残らない）" {
	make_ok_project
	rm "$P/.github/required-checks.txt"
	run_sut
	[ "$status" -eq 1 ]
	[[ "$output" == *"required-checks.txt がありません"* ]]
}

@test "赤: 宣言があるのにワークフローが無いと fail する" {
	make_ok_project
	rm "$P/.github/workflows/ci.yml"
	rmdir "$P/.github/workflows"
	run_sut
	[ "$status" -eq 1 ]
	[[ "$output" == *"workflows/ がありません"* ]]
}

# ---- 呼び出し方（fail-closed） ----

@test "exit 2: 引数が無ければ呼び出し方の誤りとして落ちる" {
	run bash "$SUT"
	[ "$status" -eq 2 ]
}

@test "exit 2: 存在しないルートを渡すと落ちる（黙って緑にしない）" {
	run bash "$SUT" "$BATS_TEST_TMPDIR/nope"
	[ "$status" -eq 2 ]
}
