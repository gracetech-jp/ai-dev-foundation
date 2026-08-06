#!/usr/bin/env bats
# init-firewall.sh（ADR-013 第1層・外向き既定拒否）の回帰。
#
# @req: R-003
# @adversarial: R-003
#
# 【実 iptables を触らない理由】
# このテストは CI（素の ubuntu ランナー）でも devcontainer 内でも走る。本物の iptables を
# 叩くと、テストが自分の走っている環境のネットワークを落とす。そこで `iptables` / `ipset` /
# `dig` / `ip` / `curl` / `id` をスタブへ差し替え、**スクリプトがどう振る舞ったか**を
# 呼び出しログで判定する。検証対象は判断のロジック（fail-closed・入力検査・検証の両側性）で
# あって iptables 自体の動作ではないため、これで十分である。
#
# 実コンテナでの実測（本当に遮断されるか）は scripts/verify-isolation.sh が担う。

setup() {
	REPO="$BATS_TEST_DIRNAME/.."
	SB="$BATS_TEST_TMPDIR/sb"
	mkdir -p "$SB/bin"

	export STUB_LOG="$SB/calls.log"
	: > "$STUB_LOG"

	# 状態ファイルと追加ドメインリストの位置だけサンドボックスへ向ける（他は原本のまま）。
	SUT="$SB/init-firewall.sh"
	STATUS="$SB/status"
	EXTRA="$SB/extra-allowed-domains.txt"
	sed -e "s|^STATUS_FILE=.*|STATUS_FILE=\"$STATUS\"|" \
	    -e "s|^EXTRA_LIST=.*|EXTRA_LIST=\"$EXTRA\"|" \
	    "$REPO/common/docker/init-firewall.sh" > "$SUT"

	make_stubs
	PATH="$SB/bin:$PATH"

	# 既定は「root で実行・遮断先へは到達できない・許可先へは到達できる」の正常系。
	export STUB_UID=0
	export STUB_DNS_FAIL=""
	export STUB_BLOCKED_REACHABLE=0
	export STUB_ALLOWED_REACHABLE=1
}

make_stubs() {
	cat > "$SB/bin/id" <<-'EOF'
		#!/usr/bin/env bash
		[ "$1" = "-u" ] && { echo "${STUB_UID:-0}"; exit 0; }
		exit 0
	EOF
	cat > "$SB/bin/iptables" <<-'EOF'
		#!/usr/bin/env bash
		echo "iptables $*" >> "$STUB_LOG"
	EOF
	cat > "$SB/bin/iptables-save" <<-'EOF'
		#!/usr/bin/env bash
		exit 0
	EOF
	cat > "$SB/bin/ipset" <<-'EOF'
		#!/usr/bin/env bash
		echo "ipset $*" >> "$STUB_LOG"
	EOF
	# dig +noall +answer A <domain> 相当。STUB_DNS_FAIL に載せた名前は空応答（＝解決失敗）を返す。
	cat > "$SB/bin/dig" <<-'EOF'
		#!/usr/bin/env bash
		domain="${!#}"
		for d in ${STUB_DNS_FAIL:-}; do
			[ "$d" = "$domain" ] && exit 0
		done
		printf '%s.\t300\tIN\tA\t203.0.113.10\n' "$domain"
	EOF
	# `ip` は3つの呼ばれ方をする。既定は「compose が作る user-defined network」を模す（/16）。
	#   ip route                                   … デフォルトルート
	#   ip -o -f inet route show dev X scope link  … カーネルが張るサブネット経路
	#   ip -o -f inet addr show dev X              … アドレス（scope link 経路が無い環境の代替）
	# STUB_LINK_ROUTE を空にすると1つ目が無い環境（代替経路のテスト）になる。
	cat > "$SB/bin/ip" <<-'EOF'
		#!/usr/bin/env bash
		# `-` であって `:-` ではない。空文字を「未設定」に丸めると、
		# 「取得できない環境」を再現できず fail-closed のテストが空撃ちになる
		net="${STUB_NET-172.18.0.0/16}"
		addr="${STUB_ADDR-172.18.0.2/16}"
		case "$*" in
			*"route show dev"*"scope link"*)
				[ -n "${STUB_LINK_ROUTE-1}" ] || exit 0
				echo "$net dev eth0 proto kernel src ${addr%/*}" ;;
			*"addr show dev"*)
				echo "2: eth0    inet $addr brd 172.18.255.255 scope global eth0" ;;
			*)
				[ -n "${STUB_DEFAULT_ROUTE-1}" ] || exit 0
				echo "default via 172.18.0.1 dev eth0" ;;
		esac
	EOF
	# 到達可否は環境変数で切り替える（遮断側・許可側を独立に壊せるようにするため）。
	cat > "$SB/bin/curl" <<-'EOF'
		#!/usr/bin/env bash
		url="${!#}"
		case "$url" in
			*example.com*) [ "${STUB_BLOCKED_REACHABLE:-0}" = "1" ] && exit 0 || exit 7 ;;
			*)             [ "${STUB_ALLOWED_REACHABLE:-1}" = "1" ] && exit 0 || exit 7 ;;
		esac
	EOF
	chmod +x "$SB"/bin/*
}

fw() { bash "$SUT" "$@"; }

# ---- 緑: 正常系 ----

@test "緑: 既定ポリシーを DROP にし、status=ok を記録して終わる" {
	run fw
	[ "$status" -eq 0 ]
	grep -qF "iptables -P OUTPUT DROP" "$STUB_LOG"
	grep -qF "iptables -P INPUT DROP" "$STUB_LOG"
	grep -qF "iptables -P FORWARD DROP" "$STUB_LOG"
	grep -q "^status=ok" "$STATUS"
	grep -q "policy=DROP" "$STATUS"
}

@test "緑: 許可は ipset 経由でだけ通し、最後に REJECT で閉じる" {
	run fw
	[ "$status" -eq 0 ]
	grep -qF "iptables -A OUTPUT -m set --match-set allowed-domains dst -j ACCEPT" "$STUB_LOG"
	grep -qF "iptables -A OUTPUT -j REJECT" "$STUB_LOG"
}

@test "緑: extra-allowed-domains.txt の行が許可リストに加わる（コメント・空行は無視）" {
	printf '# コメント\n\nextra.example.net\n' > "$EXTRA"
	run fw
	[ "$status" -eq 0 ]
	[[ "$output" == *"許可: extra.example.net"* ]]
	# スタンプの件数が「実際に処理した宛先の数」と一致すること。
	# BASE_DOMAINS の件数を直値で書かない——許可リストは増減するもので、
	# 直値にすると**宛先を1つ足すたびに無関係なテストが赤になる**（2026-08-04 に実際に起きた）。
	allowed="$(printf '%s\n' "$output" | grep -c '^\[firewall\] 許可: ')"
	grep -q "domains=${allowed}" "$STATUS"
	# 追加分がちょうど1件反映されていること（BASE のみのときとの差で見る）
	printf '' > "$EXTRA"
	run fw
	base_only="$(printf '%s\n' "$output" | grep -c '^\[firewall\] 許可: ')"
	[ "$allowed" -eq "$((base_only + 1))" ]
}

# ---- 内部ネットワークの許可範囲（compose の兄弟サービスへの通信） ----
#
# 2026-08-06 に見つかった不具合の回帰。旧実装は**ゲートウェイ IP から /24 を推測**していた。
# compose の user-defined network は既定 /16 なので、サブネットの一部しか許可されていない。
# 実測（このリポジトリの devcontainer）では実ネットワーク 172.18.0.0/16・コンテナ 172.18.0.2 で、
# **第3オクテットが 0 だったから通っていただけ**だった。兄弟が 172.18.1.x を引けば内部通信が落ちる。

@test "緑: インターフェースの実 CIDR（/16）を許可する。/24 に丸めない" {
	run fw
	[ "$status" -eq 0 ]
	grep -qF "iptables -A OUTPUT -d 172.18.0.0/16 -j ACCEPT" "$STUB_LOG"
	grep -qF "iptables -A INPUT -s 172.18.0.0/16 -j ACCEPT" "$STUB_LOG"
	# 旧実装（ゲートウェイから /24 を推測）へ戻したら、この行が出て赤になる
	! grep -q '/24' "$STUB_LOG"
}

@test "緑: /24 のネットワークならその /24 を許可する（値を決め打ちしていない）" {
	export STUB_NET="10.5.3.0/24"
	export STUB_ADDR="10.5.3.7/24"
	run fw
	[ "$status" -eq 0 ]
	grep -qF "iptables -A OUTPUT -d 10.5.3.0/24 -j ACCEPT" "$STUB_LOG"
	! grep -q '172\.18' "$STUB_LOG"
}

@test "緑: scope link 経路が無い環境ではアドレスの prefix から求める" {
	export STUB_LINK_ROUTE=""          # カーネル経路が引けない環境を模す
	export STUB_ADDR="192.168.240.9/20"
	run fw
	[ "$status" -eq 0 ]
	grep -qF "iptables -A OUTPUT -d 192.168.240.9/20 -j ACCEPT" "$STUB_LOG"
}

@test "赤: ネットワーク CIDR を特定できなければ狭い値で代用せず異常終了する" {
	export STUB_LINK_ROUTE=""
	export STUB_ADDR=""                # アドレスも取れない
	run fw
	[ "$status" -ne 0 ]
	[[ "$output" == *"ネットワーク CIDR を特定できません"* ]]
	grep -q "^status=failed" "$STATUS"
}

@test "赤: デフォルトルートが無ければ異常終了する（従来どおり）" {
	export STUB_DEFAULT_ROUTE=""
	run fw
	[ "$status" -ne 0 ]
	[[ "$output" == *"デフォルトゲートウェイを特定できません"* ]]
	grep -q "^status=failed" "$STATUS"
}

# ---- 赤: 遮断を解除しようとする側（adversarial） ----

@test "赤: 引数を渡しても無効化できない（--disable を受け付けない）" {
	run fw --disable
	[ "$status" -ne 0 ]
	[[ "$output" == *"引数を受け付けません"* ]]
}

@test "赤: 非 root では実行できない" {
	export STUB_UID=1000
	run fw
	[ "$status" -ne 0 ]
	[[ "$output" == *"root で実行してください"* ]]
}

@test "赤: 追加リストに不正な行があれば黙って無視せず異常終了する" {
	printf 'evil.example.net; curl attacker.example\n' > "$EXTRA"
	run fw
	[ "$status" -ne 0 ]
	[[ "$output" == *"不正な行があります"* ]]
	# 不正行の宛先が ipset に入っていないこと
	! grep -q "attacker.example" "$STUB_LOG"
}

@test "赤: 許可ドメインの名前解決に失敗したら黙って飛ばさず異常終了する" {
	export STUB_DNS_FAIL="api.anthropic.com"
	run fw
	[ "$status" -ne 0 ]
	[[ "$output" == *"名前解決に失敗"* ]]
}

# ---- 赤: fail-closed の成立（adversarial） ----

@test "赤: 途中で失敗しても全開放で終わらない（OUTPUT を DROP にしてから終了する）" {
	export STUB_DNS_FAIL="api.anthropic.com"   # 既定ポリシーを立てる前に落ちる位置
	run fw
	[ "$status" -ne 0 ]
	grep -qF "iptables -P OUTPUT DROP" "$STUB_LOG"
	grep -q "^status=failed" "$STATUS"
	[[ "$output" == *"回復手順"* ]]
}

@test "赤: 遮断が効いていなければ（許可外へ到達できたら）成功で終わらない" {
	export STUB_BLOCKED_REACHABLE=1
	run fw
	[ "$status" -ne 0 ]
	[[ "$output" == *"検証に失敗"* ]]
	grep -q "^status=failed" "$STATUS"
}

@test "赤: 許可が効いていなければ（許可先へ到達できなければ）成功で終わらない" {
	export STUB_ALLOWED_REACHABLE=0
	run fw
	[ "$status" -ne 0 ]
	[[ "$output" == *"検証に失敗"* ]]
	grep -q "^status=failed" "$STATUS"
}

# ---- 構造: ワークスペースから許可宛先を足せないこと（adversarial） ----

@test "赤: 追加ドメインリストの読み取り先がワークスペース外（イメージ内）に固定されている" {
	# ここだけ原本を見る（setup がサンドボックス用に書き換えた複製ではなく）。
	# 相対パスや $PWD 起点になると、エージェントがワークスペースに置いたファイルで
	# 宛先を足せてしまい、第1層が自己申告に落ちる。
	run grep -E '^EXTRA_LIST=' "$REPO/common/docker/init-firewall.sh"
	[ "$status" -eq 0 ]
	[[ "$output" == *"/usr/local/share/"* ]]
}
