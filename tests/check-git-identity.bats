#!/usr/bin/env bats
# common/scripts/check-git-identity.sh（コミット identity のローカル上書き検出）の回帰。
#
# この検査が拾うのは**症状の出ない誤り**である。2026-08-08 に sumai-desk で 346 件が
# 個人アドレスで記録されていたが、コミットは成功し、CI も赤くならず、GitHub 上も本人の
# コミットに見えていた。気づく契機が1つも無いので、機械で見るしかない。
#
# 固定したいのは3点で、どれも外れ方が静かである。
#   1. local が global と食い違えば赤（これを外すと検査ごと無意味になる）
#   2. **値そのものは判定しない**（共通側が「正しいアドレス」を持つと、共同作業者・別法人の
#      案件で必ず破綻する。特定の文字列を期待する実装へ退化していないことを固定する）
#   3. global 未設定なら未判定（CI のランナーは global を持たない。落とすと常時赤になる）
#
# 【git config --global をテストでどう扱うか】
# 実行者の ~/.gitconfig を書き換えるわけにはいかないので、HOME をテスト用ディレクトリへ
# 差し替える。これで --global の読み書きがテスト内に閉じる。

SUT="${BATS_TEST_DIRNAME}/../common/scripts/check-git-identity.sh"

setup() {
	HOME="$BATS_TEST_TMPDIR/home"
	mkdir -p "$HOME"
	export HOME
	P="$BATS_TEST_TMPDIR/proj"
	mkdir -p "$P"
	git -C "$P" init -q
}

set_global() { git config --global "$1" "$2"; }
set_local()  { git -C "$P" config --local "$1" "$2"; }
run_sut()    { run bash "$SUT" "$P"; }

# ---- 緑 ----

@test "緑: ローカル上書きが無い（global だけ）" {
	set_global user.email "corp@example.com"
	set_global user.name  "Corp User"
	run_sut
	[ "$status" -eq 0 ]
}

@test "緑: local があっても global と同値なら通す（冗長なだけで誤りではない）" {
	set_global user.email "corp@example.com"
	set_local  user.email "corp@example.com"
	run_sut
	[ "$status" -eq 0 ]
}

@test "緑: user.signingkey のローカル上書きは対象外（リポジトリごとに変えるのは正当）" {
	set_global user.email "corp@example.com"
	set_local  user.signingkey "ABCDEF0123456789"
	run_sut
	[ "$status" -eq 0 ]
}

# ---- 赤: 上書きの検出（この検査の主眼） ----

@test "赤: user.email がローカル上書きされている" {
	set_global user.email "corp@example.com"
	set_local  user.email "personal@example.net"
	run_sut
	[ "$status" -eq 1 ]
	[[ "$output" == *"user.email"* ]]
	[[ "$output" == *"personal@example.net"* ]]
	[[ "$output" == *"corp@example.com"* ]]
}

@test "赤: user.name のローカル上書きも独立に捕まえる" {
	set_global user.name "Corp User"
	set_local  user.name "handle-name"
	run_sut
	[ "$status" -eq 1 ]
	[[ "$output" == *"user.name"* ]]
}

@test "赤: email と name が両方上書きされていれば両方報告する" {
	set_global user.email "corp@example.com"
	set_global user.name  "Corp User"
	set_local  user.email "personal@example.net"
	set_local  user.name  "handle-name"
	run_sut
	[ "$status" -eq 1 ]
	[[ "$output" == *"user.email"* ]]
	[[ "$output" == *"user.name"* ]]
}

# ---- 値を判定しないこと（共通側に identity を持たせない） ----

@test "緑: 一致してさえいれば、どんな値でも通す（特定アドレスを期待しない）" {
	# 「正しいアドレス」を共通側が知る実装へ退化すると、このケースが赤になる。
	set_global user.email "someone@another-company.example"
	set_local  user.email "someone@another-company.example"
	run_sut
	[ "$status" -eq 0 ]
}

@test "赤: 法人らしいアドレス同士でも、食い違えば赤（判定基準は一致であって中身ではない）" {
	set_global user.email "a@corp.example"
	set_local  user.email "b@corp.example"
	run_sut
	[ "$status" -eq 1 ]
}

# ---- 未判定 ----

@test "未判定: global が無くローカルだけがある（CI のランナーはここに来る）" {
	set_local user.email "ci@example.com"
	run_sut
	[ "$status" -eq 0 ]
	[[ "$output" == *"未判定"* ]]
}

@test "未判定: global も local も無い" {
	run_sut
	[ "$status" -eq 0 ]
}

@test "未判定: git リポジトリではない" {
	mkdir -p "$BATS_TEST_TMPDIR/plain"
	run bash "$SUT" "$BATS_TEST_TMPDIR/plain"
	[ "$status" -eq 0 ]
	[[ "$output" == *"git リポジトリではない"* ]]
}

@test "未判定: 上位リポジトリの一部であって単独のリポジトリではない" {
	# ここを見てしまうと、別のリポジトリの .git/config を評価して緑にすることになる。
	set_global user.email "corp@example.com"
	set_local  user.email "personal@example.net"
	mkdir -p "$P/subdir"
	run bash "$SUT" "$P/subdir"
	[ "$status" -eq 0 ]
	[[ "$output" == *"単独の git リポジトリではない"* ]]
}

# ---- fail-closed ----

@test "exit 2: 引数不足は fail-closed" {
	run bash "$SUT"
	[ "$status" -eq 2 ]
}

@test "exit 2: 存在しないプロジェクトルートは fail-closed" {
	run bash "$SUT" "$BATS_TEST_TMPDIR/nope"
	[ "$status" -eq 2 ]
}
