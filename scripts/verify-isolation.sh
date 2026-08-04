#!/usr/bin/env bash
# 開発コンテナの隔離境界（ADR-013 第1層）が実際に効いているかを、動いているコンテナの中から確認する。
#
# Rebuild のたびに1回流す想定。設定ファイルが正しいことは audit-consistency.sh の検査(13)が見るが、
# 「その設定で実際に遮断されているか」はコンテナを動かさないと分からない。ここはその実測を担う。
#
# 【iptables のルールを直接読まない理由】
# sudo は init-firewall.sh 1本だけに絞ってあり、非 root では iptables のルールを読めない
# （読めるということは消せるということでもある）。そこで確認は次の2本立てで行う。
#   1. init-firewall.sh が残す状態スタンプ（/var/log/init-firewall.status）
#   2. 実際に通信してみた結果（許可先に届き、許可外に届かないこと）
# 「ルールがこう書いてある」ではなく「実際にこう振る舞う」で判定する。

set -uo pipefail

STATUS_FILE="/var/log/init-firewall.status"
BLOCKED_URL="https://example.com"
ALLOWED_URL="https://api.anthropic.com"

pass=0
fail=0

ok()   { echo "  ✅ $1"; pass=$((pass + 1)); }
ng()   { echo "  ❌ $1"; fail=$((fail + 1)); }
head2() { echo ""; echo "[$1] $2"; }

head2 1/5 "init-firewall.sh が実際に走ったか"
if [ ! -f "$STATUS_FILE" ]; then
	ng "$STATUS_FILE がありません（postStartCommand が走っていない可能性）"
	echo "     → devcontainer.json の postStartCommand を確認し、コンテナを再起動する"
else
	status="$(sed -n 's/^status=//p' "$STATUS_FILE" | head -1)"
	at="$(sed -n 's/^at=//p' "$STATUS_FILE" | head -1)"
	detail="$(sed -n 's/^detail=//p' "$STATUS_FILE" | head -1)"
	case "$status" in
		ok)     ok "適用済み（$at / $detail）" ;;
		failed) ng "適用に失敗して全遮断で終了しています（$at / $detail）" ;;
		*)      ng "状態を判別できません: '$status'" ;;
	esac
fi

head2 2/5 "既定ポリシーが DROP になっているか"
# 非 root ではポリシーを読めないため、スクリプトが記録した適用内容で確認する。
# 実際の振る舞いは 3/5 が受け持つ（記録と実測の両方が揃って初めて信頼できる）。
if [ -f "$STATUS_FILE" ] && grep -q 'policy=DROP' "$STATUS_FILE"; then
	ok "既定ポリシー DROP を適用した記録がある"
else
	ng "DROP を適用した記録がない（1/5 が失敗しているならそちらが原因）"
fi

head2 3/5 "許可リスト外への通信が実際に遮断されるか"
if curl --connect-timeout 5 -s -o /dev/null "$BLOCKED_URL" 2>/dev/null; then
	ng "$BLOCKED_URL へ到達できてしまいました（遮断が効いていません）"
else
	ok "$BLOCKED_URL へ到達できない（期待どおり）"
fi
if curl --connect-timeout 5 -s -o /dev/null "$ALLOWED_URL" 2>/dev/null; then
	ok "$ALLOWED_URL へ到達できる（許可が効いている）"
else
	ng "$ALLOWED_URL へ到達できません（許可リストが機能していないか、IP が変わった可能性）"
	echo "     → コンテナを再起動すると名前解決からやり直す"
fi

head2 4/5 "sudo が init-firewall.sh 以外で使えないこと"
if id -nG | tr ' ' '\n' | grep -qx sudo; then
	ng "node が sudo グループに属しています（gpasswd -d node sudo が効いていない）"
else
	ok "sudo グループに属していない"
fi
if sudo -n true 2>/dev/null; then
	ng "任意のコマンドを sudo で実行できます（NOPASSWD:ALL が残っています）"
else
	ok "任意コマンドの sudo は拒否される"
fi
if sudo -n -l 2>/dev/null | grep -q '/usr/local/bin/init-firewall.sh'; then
	ok "init-firewall.sh のみ sudo で実行できる"
else
	# ここが落ちてもファイアウォールは既に適用済みなので致命ではないが、
	# 次回の起動で postStartCommand が失敗するため赤にする
	ng "init-firewall.sh を sudo で実行できません（次回起動時に遮断が適用されません）"
fi

head2 5/5 "品質ゲート（make audit-all / make test）"
if make -C /workspace audit-all >/dev/null 2>&1; then
	ok "make audit-all 緑"
else
	ng "make audit-all 赤（詳細: make audit-all）"
fi
if test_out="$(make -C /workspace test 2>&1)"; then
	ok "make test 緑（$(printf '%s' "$test_out" | grep -cE '^ok ') ケース）"
else
	ng "make test 赤（詳細: make test）"
	printf '%s\n' "$test_out" | grep -E '^not ok' | sed 's/^/     /'
fi

echo ""
echo "=========================================="
if [ "$fail" -eq 0 ]; then
	echo " ✅ 隔離境界の確認: 全 $pass 項目に問題なし"
	echo "=========================================="
	exit 0
fi
echo " ❌ 隔離境界の確認: $fail 件の問題（成功 $pass 件）"
echo "    回復手順: docs/rules/security.md「遮断で詰まったときの回復手順」"
echo "    回復はホスト側で行う（コンテナ内から遮断を解除する口は用意していない）"
echo "=========================================="
exit 1
