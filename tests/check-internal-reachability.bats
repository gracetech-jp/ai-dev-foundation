#!/usr/bin/env bats
# common/scripts/check-internal-reachability.sh（遮断してはいけない内部通信の実測）の回帰。
#
# この検査だけ方向が逆で、守るのは「**通るべきものが通ること**」である。
# 外れ方は1種類だが、それが静かに起きる:
#   ファイアウォールを締めすぎて兄弟コンテナへ届かなくなる → make test も E2E も全滅する。
# 遮断側だけを測っていると「全部止めても緑」になり、この形を1件も捕まえられない。
#
# 到達する／しないを本物のソケットで作る（モックにすると、判定ロジックではなくモックを試すことになる）。
#   到達する   … 127.0.0.1 で http.server を上げる（HTTP と TCP の両方の宛先として使える）
#   到達しない … 一度 bind して即座に閉じたポート（誰も listen していない＝接続拒否）
#
# 各ケースは「正常な構成を作ってから1箇所だけ壊す」（変異注入）。

SUT="${BATS_TEST_DIRNAME}/../common/scripts/check-internal-reachability.sh"

# 空きポートを1つ得る。得た直後は誰も listen していないので、そのまま使えば「到達しない」宛先になる。
free_port() {
	python3 -c 'import socket
s = socket.socket()
s.bind(("127.0.0.1", 0))
print(s.getsockname()[1])
s.close()'
}

setup() {
	P="$BATS_TEST_TMPDIR/proj"
	mkdir -p "$P/.devcontainer"
	DECL="$P/.devcontainer/internal-targets.txt"
	DEAD_PORT="$(free_port)"
	SERVER_PID=""
}

teardown() {
	[ -n "${SERVER_PID:-}" ] && kill "$SERVER_PID" 2>/dev/null
	return 0
}

# 127.0.0.1 に HTTP リスナーを立て、応答するまで待つ。待たずに測ると起動競合で偽の赤が出る。
start_server() {
	LIVE_PORT="$(free_port)"
	python3 -m http.server "$LIVE_PORT" --bind 127.0.0.1 >/dev/null 2>&1 &
	SERVER_PID=$!
	for _ in $(seq 1 50); do
		if curl -s -o /dev/null --connect-timeout 1 "http://127.0.0.1:$LIVE_PORT/"; then return 0; fi
		sleep 0.1
	done
	return 1
}

run_sut() { run bash "$SUT" "$P"; }

# ---- 未判定 ----

@test "未判定: 宣言ファイルが無い（compose 方式でないプロジェクト）" {
	run_sut
	[ "$status" -eq 0 ]
	[[ "$output" == *"未判定"* ]]
}

# ---- 緑 ----

@test "緑: HTTP の到達先へ届く" {
	start_server
	printf 'http://127.0.0.1:%s/\n' "$LIVE_PORT" > "$DECL"
	run_sut
	[ "$status" -eq 0 ]
}

@test "緑: host:port（TCP のみ）の到達先へ届く" {
	start_server
	printf '127.0.0.1:%s\n' "$LIVE_PORT" > "$DECL"
	run_sut
	[ "$status" -eq 0 ]
}

@test "緑: コメント・空行・前後の空白は無視される" {
	start_server
	printf '# 兄弟サービス\n\n   http://127.0.0.1:%s/   # backend\n\n' "$LIVE_PORT" > "$DECL"
	run_sut
	[ "$status" -eq 0 ]
}

@test "緑: HTTP ステータスが 404 でも到達とみなす（測るのは経路であってアプリではない）" {
	start_server
	printf 'http://127.0.0.1:%s/no-such-path\n' "$LIVE_PORT" > "$DECL"
	run_sut
	[ "$status" -eq 0 ]
}

# ---- 赤: 遮断のしすぎ（この検査の主眼） ----

@test "赤: HTTP の到達先へ届かない" {
	printf 'http://127.0.0.1:%s/\n' "$DEAD_PORT" > "$DECL"
	run_sut
	[ "$status" -eq 1 ]
	[[ "$output" == *"到達できません"* ]]
}

@test "赤: host:port（TCP）へ届かない" {
	printf '127.0.0.1:%s\n' "$DEAD_PORT" > "$DECL"
	run_sut
	[ "$status" -eq 1 ]
	[[ "$output" == *"到達できません"* ]]
}

@test "赤: 複数のうち1件だけ届かなくても赤（他が緑でも埋もれさせない）" {
	start_server
	printf 'http://127.0.0.1:%s/\n127.0.0.1:%s\n' "$LIVE_PORT" "$DEAD_PORT" > "$DECL"
	run_sut
	[ "$status" -eq 1 ]
	[[ "$output" == *"$DEAD_PORT"* ]]
	[[ "$output" == *"✅"* ]]   # 届いたほうは緑で出る
}

# ---- 赤: 検査が空回りする形 ----

@test "赤: 宣言ファイルはあるのに到達先が0件（全部コメントアウト）" {
	printf '# 全部コメントアウトした\n\n' > "$DECL"
	run_sut
	[ "$status" -eq 1 ]
	[[ "$output" == *"1件もありません"* ]]
}

# ---- exit 2: 宣言の誤りを「到達できない」と混同しない ----

@test "exit 2: 書式が不正（http でも host:port でもない）" {
	printf 'backend\n' > "$DECL"
	run_sut
	[ "$status" -eq 2 ]
	[[ "$output" == *"書式が不正"* ]]
}

@test "exit 2: ポートが数値でない" {
	printf 'backend:http\n' > "$DECL"
	run_sut
	[ "$status" -eq 2 ]
}

@test "exit 2: ポートが範囲外" {
	printf 'backend:70000\n' > "$DECL"
	run_sut
	[ "$status" -eq 2 ]
}

@test "exit 2: スキームだけでホスト名が無い" {
	printf 'http:///health\n' > "$DECL"
	run_sut
	[ "$status" -eq 2 ]
}

@test "exit 2: 書式の誤りは、到達できる宛先が並んでいても先に落とす" {
	# 誤りを「到達できない」と混同すると、タイポをファイアウォールの問題として調べることになる。
	start_server
	printf 'http://127.0.0.1:%s/\nbackend\n' "$LIVE_PORT" > "$DECL"
	run_sut
	[ "$status" -eq 2 ]
}

@test "exit 2: 引数不足は fail-closed" {
	run bash "$SUT"
	[ "$status" -eq 2 ]
}

@test "exit 2: 存在しないプロジェクトルートは fail-closed" {
	run bash "$SUT" "$P/nope"
	[ "$status" -eq 2 ]
}
