#!/usr/bin/env bash
# 開発コンテナの外向きネットワークを既定拒否にする（ADR-013 第1層）。
#
# 【この層の位置づけ】
# ADR-012 で「本物の境界はコンテナ隔離だけ」と決めた。permissions.deny も PreToolUse フックも
# 迂回経路が実証されており、敵対的コードに対する防御としては数えない。実際に爆発半径を決めるのは
# ここ——コンテナから外へ出られる宛先の集合——である。
#
# 【実行経路（重要）】
# devcontainer.json の postStartCommand から `sudo /usr/local/bin/init-firewall.sh` で呼ぶ。
# sudoers はこの絶対パス1本だけを NOPASSWD で許す。**実行されるのはイメージへ焼いた root 所有の
# コピーであって、マウントされたワークスペース側のファイルではない**。ワークスペース側を実行対象に
# すると、エージェントがスクリプトを書き換えて sudo する＝root 昇格経路になる。
# 同じ理由で、許可ドメインもワークスペースから読まない（下記 EXTRA_LIST もイメージ内に焼く）。
#
# 【引数を取らない】
# sudoers は引数まで固定できない。`--disable` のような無効化オプションを持たせると、
# コンテナ内から遮断を解除できてしまい第1層の意味が消える。回復はホスト側で行う
# （docs/rules/security.md の回復手順）。
#
# 【許可ドメインの根拠】
# 公式の Network access requirements（code.claude.com/docs/en/network-config）に挙がる必須ホストと、
# 2026-08-04 に実コンテナで観測した宛先（tcpdump）の積で決めた。参照実装が挙げる sentry.io /
# statsig.* は公式の必須表に無いため入れていない。運用テレメトリ（Datadog 2ホスト）は
# 許可せず、containerEnv の CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC で送信自体を止める。
#
# 【既知の限界】
# 名前解決の結果を ipset に固定するため、CDN の IP ローテーションで到達できなくなることがある。
# その場合はコンテナを再起動すれば再解決される（回復手順に含める）。

set -euo pipefail
IFS=$'\n\t'

BASE_DOMAINS=(
	"api.anthropic.com"          # Claude API 本体・WebFetch の事前チェック・機能フラグ
	"claude.ai"                  # claude.ai アカウント認証
	"claude.com"                 # サインイン導線・事前承認済み WebFetch
	"platform.claude.com"        # OAuth トークンの交換／更新（claude.ai ログインでも必要）
	"mcp-proxy.anthropic.com"    # claude.ai コネクタ経由の MCP（2026-08-04 実測で観測）
	"downloads.claude.ai"        # ネイティブインストーラと自動更新（Dockerfile が install.sh を使う）
	"storage.googleapis.com"     # プラグインのメタデータ・旧版インストーラ
	"raw.githubusercontent.com"  # /release-notes の変更履歴フィード
	"code.claude.com"            # ドキュメント参照（2026-08-04 実測で観測）
	# GitHub（2026-08-04 追加・ADR-013 の判断変更）。CI 結果と Actions の状態をエージェント自身が
	# 確認できるようにするため。ホスト側で gh を叩く運用は「極力人間に手を使わない」前提に反する。
	# **爆発半径は明確に広がる**（コンテナから git push と API 操作が可能になる）。
	# 実際に何ができるかを決めるのは、この行ではなく**渡すトークンのスコープ**である。
	"api.github.com"             # gh の REST/GraphQL（CI 結果・Actions の状態・リポジトリ設定）
	"github.com"                 # git over HTTPS（fetch / pull / push）・gh の一部導線
	# 足していないもの（用途が確定していないため。R-003「推測で足さない」）:
	#   codeload.github.com … アーカイブ取得（gh release download / tarball）
	#   uploads.github.com  … アップロード（gh release upload）
	# 必要になったら、失敗したコマンドのエラーを根拠に1件ずつ足す。
	#
	# なお objects.githubusercontent.com は**足さなくても到達する**。raw.githubusercontent.com と
	# 同じ4つの IP（185.199.108-111.133）に解決されるため、ipset では区別できない（2026-08-04 実測）。
	# これは R-003「対象外」に挙げた「同一 IP への相乗り」がそのまま現れた例である。
)

# プロジェクト固有の追加分。**イメージ内**にしか置かない（ワークスペースから読むと
# エージェントが宛先を足せてしまう）。Dockerfile の COPY で焼く。
EXTRA_LIST="/usr/local/share/extra-allowed-domains.txt"

# 到達確認に使う宛先。許可リストに実在するものから選ぶ（固定の外部ホストに依存しない）
VERIFY_ALLOWED="https://api.anthropic.com"
VERIFY_BLOCKED="https://example.com"

# 適用結果の記録先。sudo を1本に絞った結果、非 root では iptables のルールを読めない
# （読めてしまうなら消せてしまう）。「本当に適用されたのか」を後から確かめる唯一の手段が
# これになるため、成功・失敗の両方を必ず書く。root 所有・全員読み取り可。
STATUS_FILE="/var/log/init-firewall.status"

write_status() {
	# write_status <ok|failed> <補足>
	{
		echo "status=$1"
		echo "at=$(date -Is)"
		echo "detail=$2"
	} > "$STATUS_FILE" 2>/dev/null || true
	chmod 0444 "$STATUS_FILE" 2>/dev/null || true
}

die() {
	echo "[firewall] ❌ $1" >&2
	exit 1
}

# 異常終了時は「開いたまま」にしない。許可リストの構築途中で落ちても全遮断してから終わる。
# 参照実装はここが fail-open で、GitHub メタ情報の取得に失敗すると全開放のまま立ち上がる。
fail_closed() {
	local rc=$1
	echo "[firewall] ⚠️ 設定に失敗しました（exit=$rc）。fail-closed で全遮断します。" >&2
	write_status "failed" "exit=$rc（全遮断で終了。ホスト側で回復すること）"
	iptables -P INPUT DROP 2>/dev/null || true
	iptables -P FORWARD DROP 2>/dev/null || true
	iptables -P OUTPUT DROP 2>/dev/null || true
	iptables -A OUTPUT -o lo -j ACCEPT 2>/dev/null || true
	cat >&2 <<-'EOF'
		[firewall] 回復手順（コンテナ内からは解除できない。ホスト側で行う）:
		  1. ホストのターミナルで .devcontainer/devcontainer.json を開く
		  2. "postStartCommand" の行を一時的に削除する
		  3. VS Code で Dev Containers: Rebuild Container を実行する
		  4. 原因（到達できなかったドメイン等）を直してから 2 を元に戻す
		  詳細: docs/rules/security.md
	EOF
}
trap 'rc=$?; [ "$rc" -eq 0 ] || fail_closed "$rc"; exit "$rc"' EXIT

[ "$#" -eq 0 ] || die "このスクリプトは引数を受け付けません（無効化オプションを持たない設計です）"
[ "$(id -u)" -eq 0 ] || die "root で実行してください（postStartCommand から sudo 経由で呼ばれます）"

for cmd in iptables ipset dig ip curl; do
	command -v "$cmd" >/dev/null 2>&1 || die "$cmd がありません（Dockerfile の導入漏れ）"
done

# 1. Docker 内部 DNS の nat ルールだけは消す前に退避する（消すと名前解決ごと死ぬ）
docker_dns_rules="$(iptables-save -t nat | grep '127\.0\.0\.11' || true)"

iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X
iptables -t mangle -F
iptables -t mangle -X
ipset destroy allowed-domains 2>/dev/null || true

if [ -n "$docker_dns_rules" ]; then
	iptables -t nat -N DOCKER_OUTPUT 2>/dev/null || true
	iptables -t nat -N DOCKER_POSTROUTING 2>/dev/null || true
	echo "$docker_dns_rules" | xargs -L 1 iptables -t nat
fi

# 2. 遮断より先に、遮断してはいけないものを通す
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
iptables -A INPUT -p udp --sport 53 -j ACCEPT
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT

# 3. 許可ドメインを名前解決して ipset へ入れる
ipset create allowed-domains hash:net

domains=("${BASE_DOMAINS[@]}")
if [ -f "$EXTRA_LIST" ]; then
	while IFS= read -r line; do
		line="${line%%#*}"
		line="$(printf '%s' "$line" | tr -d '[:space:]')"
		[ -n "$line" ] || continue
		# 焼き込み済みのファイルとはいえ、書式は検査する（壊れた行を黙って無視しない）
		printf '%s' "$line" | grep -qE '^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?$' \
			|| die "$EXTRA_LIST に不正な行があります: $line"
		domains+=("$line")
	done < "$EXTRA_LIST"
fi

for domain in "${domains[@]}"; do
	ips="$(dig +noall +answer A "$domain" | awk '$4 == "A" {print $5}')"
	[ -n "$ips" ] || die "$domain の名前解決に失敗しました（DNS が通らないか、綴りが違います）"
	while IFS= read -r ip; do
		[ -n "$ip" ] || continue
		printf '%s' "$ip" | grep -qE '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$' \
			|| die "$domain の DNS 応答が IPv4 として不正です: $ip"
		ipset add allowed-domains "$ip" 2>/dev/null || true
	done <<< "$ips"
	echo "[firewall] 許可: $domain"
done

# 4. ホストとの通信（VS Code のリモート接続・ポート転送）は通す
host_ip="$(ip route | awk '/^default/ {print $3; exit}')"
[ -n "$host_ip" ] || die "デフォルトゲートウェイを特定できません"
host_network="${host_ip%.*}.0/24"
iptables -A INPUT -s "$host_network" -j ACCEPT
iptables -A OUTPUT -d "$host_network" -j ACCEPT

# 5. 既定拒否にしてから、許可済みだけを通す
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT DROP
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m set --match-set allowed-domains dst -j ACCEPT
# DROP ではなく REJECT。握り潰されて「なぜか遅い」になるより、即座に失敗させて原因を見せる
iptables -A OUTPUT -j REJECT --reject-with icmp-admin-prohibited

# 6. 効いていることを両側から確認する（片側だけだと「全部塞いだ」でも通ってしまう）
if curl --connect-timeout 5 -s -o /dev/null "$VERIFY_BLOCKED" 2>/dev/null; then
	die "検証に失敗: $VERIFY_BLOCKED へ到達できました（遮断が効いていません）"
fi
if ! curl --connect-timeout 5 -s -o /dev/null "$VERIFY_ALLOWED" 2>/dev/null; then
	die "検証に失敗: $VERIFY_ALLOWED へ到達できません（許可が効いていません）"
fi

write_status "ok" "policy=DROP domains=${#domains[@]}"
echo "[firewall] ✅ 外向き既定拒否を適用しました（許可 ${#domains[@]} ドメイン）"
