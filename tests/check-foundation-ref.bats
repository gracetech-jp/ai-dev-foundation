#!/usr/bin/env bats
# common/scripts/check-foundation-ref.sh（`uses: ...@X` と `foundation-ref: Y` の一致）の回帰。
#
# この二重記述は 2026-08-06 の実測（計画書 §8-5）でやむなく生まれた。
# `github.job_workflow_sha` も `job_workflow_ref` も空で、未指定だと共通基盤の checkout が
# 既定ブランチへ落ちる——`@v2` でピン止めしても main のコードでゲートが回る。
#
# 固定したいのは「ずれても赤くならない」という性質のほう。ゲートは走り緑になり、
# 違うのは**どの版のゲートで検査したか**だけなので、人間の目には何も起きない。
# だから機械で見る。各ケースは正常形を1箇所だけ壊す（変異注入）。

SUT="${BATS_TEST_DIRNAME}/../common/scripts/check-foundation-ref.sh"

setup() {
	P="$BATS_TEST_TMPDIR/proj"
	mkdir -p "$P/.github/workflows"
}

# 正常形: uses と foundation-ref が同じ ref を指す
make_ok() {
	printf 'name: CI\non:\n  pull_request:\n\njobs:\n  ci:\n    uses: gracetech-jp/ai-dev-foundation/.github/workflows/service-ci.yml@v2\n    with:\n      project-name: svc\n      foundation-ref: v2\n' > "$P/.github/workflows/ci.yml"
}

run_sut() { run bash "$SUT" "$P"; }

@test "緑: uses と foundation-ref が一致していれば通る" {
	make_ok
	run_sut
	[ "$status" -eq 0 ]
}

@test "赤: ref がずれていると fail する（版が食い違ったまま緑になる状態を潰す）" {
	make_ok
	sed -i 's/^      foundation-ref: v2/      foundation-ref: v1/' "$P/.github/workflows/ci.yml"
	run_sut
	[ "$status" -eq 1 ]
	[[ "$output" == *"ref がずれています"* ]]
}

@test "赤: foundation-ref を省くと fail する（既定ブランチへ落ちてピン止めが無効になる）" {
	make_ok
	sed -i '/foundation-ref/d' "$P/.github/workflows/ci.yml"
	run_sut
	[ "$status" -eq 1 ]
	[[ "$output" == *"foundation-ref がありません"* ]]
}

@test "緑: 式で渡す場合は workflow_dispatch 入力の default と突き合わせる" {
	printf 'name: selftest\non:\n  workflow_dispatch:\n    inputs:\n      foundation-ref:\n        type: string\n        default: main\n\njobs:\n  selftest:\n    uses: gracetech-jp/ai-dev-foundation/.github/workflows/service-ci.yml@main\n    with:\n      foundation-ref: ${{ inputs.foundation-ref }}\n' > "$P/.github/workflows/selftest.yml"
	run_sut
	[ "$status" -eq 0 ]
}

@test "赤: 式で渡していて default が uses とずれていれば fail する" {
	printf 'name: selftest\non:\n  workflow_dispatch:\n    inputs:\n      foundation-ref:\n        type: string\n        default: v1\n\njobs:\n  selftest:\n    uses: gracetech-jp/ai-dev-foundation/.github/workflows/service-ci.yml@main\n    with:\n      foundation-ref: ${{ inputs.foundation-ref }}\n' > "$P/.github/workflows/selftest.yml"
	run_sut
	[ "$status" -eq 1 ]
	[[ "$output" == *"ref がずれています"* ]]
}

@test "赤: 式で渡していて既定値をたどれなければ fail する（黙って緑にしない）" {
	printf 'name: selftest\non:\n  workflow_dispatch:\n    inputs:\n      foundation-ref:\n        type: string\n\njobs:\n  selftest:\n    uses: gracetech-jp/ai-dev-foundation/.github/workflows/service-ci.yml@main\n    with:\n      foundation-ref: ${{ inputs.foundation-ref }}\n' > "$P/.github/workflows/selftest.yml"
	run_sut
	[ "$status" -eq 1 ]
	[[ "$output" == *"既定値をたどれません"* ]]
}

@test "緑: 行末コメント付きでも値として誤読しない" {
	# 実装時に踏んだ: `foundation-ref: v2   # 説明` のコメントまで値に含めて不一致にしていた
	make_ok
	sed -i 's|^      foundation-ref: v2$|      foundation-ref: v2   # uses: と同じ ref|' "$P/.github/workflows/ci.yml"
	run_sut
	[ "$status" -eq 0 ]
}

@test "緑: reusable を呼んでいないワークフローは対象外" {
	printf 'name: CI\non:\n  pull_request:\n\njobs:\n  test:\n    runs-on: ubuntu-latest\n    steps:\n      - run: make test\n' > "$P/.github/workflows/ci.yml"
	run_sut
	[ "$status" -eq 0 ]
}

@test "緑: .github/workflows が無いリポジトリは対象外" {
	rmdir "$P/.github/workflows"
	run_sut
	[ "$status" -eq 0 ]
}

@test "exit 2: 引数が無ければ呼び出し方の誤りとして落ちる" {
	run bash "$SUT"
	[ "$status" -eq 2 ]
}
