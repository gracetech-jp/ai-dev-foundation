#!/usr/bin/env bats
# common/scripts/run-common-audits.sh（共通監査の集約とドリフト検出）の回帰。
#
# このスクリプトが解くのはテンプレートドリフトである。共通検査の判定は既に共通側にあったのに、
# **呼ぶ側**が各リポジトリへ複製されていたため、基盤に検査を足しても届かなかった
# （実際に2件溜まり、grace-tech-hp では5件欠落していた）。
#
# 固定したいのは3点。
#   1. 一覧に足せば全部が走る（集約が集約として機能していること）
#   2. 契約番号がずれたら赤（**集約しても、古い前提のまま呼ぶリポジトリは残る**。
#      黙って緑になるとドリフト検出が空回りする）
#   3. 1つ落ちても後続は走る（1回で全部の結果が出ないと直すのに何往復もかかる）
#
# 【偽の共通ツリーを作る理由】
# 本体は自分の位置から共通スクリプト群を決める。実物を呼ぶと実際の検査が走ってしまい、
# 集約の挙動ではなく個々の検査を試すことになる。ここでは検査をスタブへ差し替える。

SUT="${BATS_TEST_DIRNAME}/../common/scripts/run-common-audits.sh"

# 本体が呼ぶ検査スクリプト名（CHECKS の並びと一致させる）
CHECK_NAMES="check-guardrail-duplication.sh check-required-checks.sh check-foundation-ref.sh check-git-hooks.sh check-git-identity.sh"

setup() {
	F="$BATS_TEST_TMPDIR/foundation"
	mkdir -p "$F/common/scripts"
	cp "$SUT" "$F/common/scripts/run-common-audits.sh"
	P="$F/projects/proj"
	mkdir -p "$P"
	# 既定は全部が緑を返すスタブ。呼ばれた事実を記録させる。
	for n in $CHECK_NAMES; do
		printf '#!/bin/sh\necho "STUB %s ran"\nexit 0\n' "$n" > "$F/common/scripts/$n"
		chmod +x "$F/common/scripts/$n"
	done
}

# 特定のスタブを差し替える
stub() { # <name> <exit-code>
	printf '#!/bin/sh\necho "STUB %s ran"\nexit %s\n' "$1" "$2" > "$F/common/scripts/$1"
	chmod +x "$F/common/scripts/$1"
}

run_sut() { run bash "$F/common/scripts/run-common-audits.sh" "$P" "${1:-1}"; }

# ---- 緑 ----

@test "緑: 全検査が通れば exit 0" {
	run_sut
	[ "$status" -eq 0 ]
}

@test "緑: 一覧の検査が全部走る（集約が機能していること）" {
	run_sut
	for n in $CHECK_NAMES; do
		[[ "$output" == *"STUB $n ran"* ]] || { echo "呼ばれていない: $n"; false; }
	done
}

@test "緑: プロジェクトルートが各検査へ渡る" {
	printf '#!/bin/sh\necho "ARG=$1"\nexit 0\n' > "$F/common/scripts/check-git-hooks.sh"
	chmod +x "$F/common/scripts/check-git-hooks.sh"
	run_sut
	[[ "$output" == *"ARG=$P"* ]]
}

# ---- 赤: 検査の失敗 ----

@test "赤: 1つでも検査が落ちれば exit 1" {
	stub check-git-hooks.sh 1
	run_sut
	[ "$status" -eq 1 ]
}

@test "赤: 1つ落ちても後続の検査は走る（1回で全部の結果を出す）" {
	stub check-guardrail-duplication.sh 1
	run_sut
	[ "$status" -eq 1 ]
	[[ "$output" == *"STUB check-git-identity.sh ran"* ]]
}

# ---- ドリフト検出（契約番号） ----

@test "赤: 宣言が共通側より古いと赤（新しい検査を把握していないリポジトリ）" {
	run_sut 0
	[ "$status" -eq 1 ]
	[[ "$output" == *"契約がずれています"* ]]
	[[ "$output" == *"上げること"* ]]
}

@test "赤: 宣言が共通側より新しいと赤（参照している共通基盤が古い）" {
	run_sut 99
	[ "$status" -eq 1 ]
	[[ "$output" == *"共通基盤のほうが古い"* ]]
}

@test "赤: 契約がずれていても検査自体は走る（ずれを理由に検査を飛ばさない）" {
	run_sut 0
	[ "$status" -eq 1 ]
	[[ "$output" == *"STUB check-git-hooks.sh ran"* ]]
}

@test "緑: 宣言が一致していればドリフトの指摘は出ない" {
	run_sut 1
	[ "$status" -eq 0 ]
	[[ "$output" != *"契約がずれています"* ]]
}

# ---- fail-closed ----

@test "exit 2: 共通検査のスクリプトが欠けていたら fail-closed（検査なしで素通しさせない）" {
	rm "$F/common/scripts/check-git-identity.sh"
	run_sut
	[ "$status" -eq 2 ]
}

@test "exit 2: 引数不足は fail-closed" {
	run bash "$F/common/scripts/run-common-audits.sh" "$P"
	[ "$status" -eq 2 ]
}

@test "exit 2: 契約番号が数値でないと fail-closed（黙って 0 扱いにしない）" {
	run bash "$F/common/scripts/run-common-audits.sh" "$P" "v1"
	[ "$status" -eq 2 ]
}

@test "exit 2: 存在しないプロジェクトルートは fail-closed" {
	run bash "$F/common/scripts/run-common-audits.sh" "$F/nope" 1
	[ "$status" -eq 2 ]
}
