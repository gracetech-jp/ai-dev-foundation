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

# GH_TOKEN に許可したリポジトリ（R-003「GitHub へ渡す資格情報のスコープ」の正本と一致させる）。
# ここが増えたら爆発半径が広がっているので、値だけ直して済ませず R-003 側も更新すること。
ALLOWED_REPOS=(
	"gracetech-jp/ai-dev-foundation"
	"gracetech-jp/grace-tech-hp"
	"gracetech-jp/sumai-desk"
)
# 書き込み拒否を測る先。**存在するリポジトリでなければならない**（不在なら 404 で、
# 権限不足の 403 と区別できない）。
WRITE_PROBE_REPO="gracetech-jp/ai-dev-foundation"

pass=0
fail=0

ok()   { echo "  ✅ $1"; pass=$((pass + 1)); }
ng()   { echo "  ❌ $1"; fail=$((fail + 1)); }
head2() { echo ""; echo "[$1] $2"; }

head2 1/6 "init-firewall.sh が実際に走ったか"
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

head2 2/6 "既定ポリシーが DROP になっているか"
# 非 root ではポリシーを読めないため、スクリプトが記録した適用内容で確認する。
# 実際の振る舞いは 3/5 が受け持つ（記録と実測の両方が揃って初めて信頼できる）。
if [ -f "$STATUS_FILE" ] && grep -q 'policy=DROP' "$STATUS_FILE"; then
	ok "既定ポリシー DROP を適用した記録がある"
else
	ng "DROP を適用した記録がない（1/5 が失敗しているならそちらが原因）"
fi

head2 3/6 "許可リスト外への通信が実際に遮断されるか"
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

head2 4/6 "sudo が init-firewall.sh 以外で使えないこと"
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

head2 5/6 "GH_TOKEN のスコープが実際に効いているか"
# 許可リストへ github.com / api.github.com を入れた時点で、この境界の実効範囲を決めるのは
# 許可リストではなく**コンテナへ渡すトークンのスコープ**になった（ADR-013 の判断変更）。
# したがってスコープも実測の対象に含める。
#
# 【`gh api /user` を使わない理由（2026-08-04）】
# fine-grained PAT は Metadata: Read-only の範囲で公開プロフィールを返すため、**常に 200 になる**。
# 「トークンが生きていること」は分かるが、スコープが絞られているかは何も分からない——
# スコープを全開放しても緑のままで、検査として無意味だった。
#
# 【「許可外リポジトリが 404」も、そのままでは使えない（同日の実測）】
#   - 許可外でも**公開**リポジトリは 200 で読めた（`octocat/Hello-World` / `anthropics/claude-code`）。
#     fine-grained PAT は選択外でも公開データには届く。
#   - 存在しないリポジトリ名は当然 404。**スコープを全開放しても 404 のまま**なので、
#     `gh api /user` と同じ「常に通る」検査の裏返しにしかならない。
#   - 許可外の**非公開**リポジトリなら 404 が意味を持つが、対象組織のリポジトリは3本とも
#     許可対象で、条件を満たす宛先が存在しない。
# そこで、スコープが広がったときに**結果が変わる**ことを条件に、次の3点で測る。
if ! command -v gh >/dev/null 2>&1; then
	ng "gh が入っていません（イメージに含めているはず。Rebuild されていない可能性）"
elif [ -z "${GH_TOKEN:-}" ]; then
	# 未設定を「スキップ」にすると、トークンが無い状態が緑になってしまう。
	# 「止まることだけを確認する検査は全部止める設定でも緑になる」のと同じ穴なので赤にする。
	ng "GH_TOKEN が空です（devcontainer.json の containerEnv 経由でホストから渡す。ホスト側で export されているか確認）"
else
	# (a) 許可側に届くこと。3/6 の「許可先へ到達できること」と同じ理由で、
	#     拒否の確認だけでは「全部拒否」の状態も緑になる。
	if gh api "repos/${WRITE_PROBE_REPO}/actions/runs" --jq '.total_count' >/dev/null 2>&1; then
		ok "許可リポジトリの Actions を読める（Actions: Read が効いている）"
	else
		ng "許可リポジトリの Actions を読めません（トークンの期限切れ・権限不足の可能性）"
	fi

	# (b) 到達できるリポジトリの集合が想定どおりであること。
	#     fine-grained PAT では user/repos が**選択したリポジトリだけ**を返すため、
	#     ここは選択範囲そのものの写しになる。増えていれば爆発半径が広がっている。
	actual="$(gh api 'user/repos?per_page=100' --jq '.[].full_name' 2>/dev/null | sort | tr '\n' ' ')"
	expected="$(printf '%s\n' "${ALLOWED_REPOS[@]}" | sort | tr '\n' ' ')"
	if [ "$actual" = "$expected" ]; then
		ok "到達できるリポジトリは想定の3本のみ"
	else
		ng "到達できるリポジトリが想定と違います（想定: ${expected}/ 実際: ${actual:-なし}）"
		echo "     → 増えているならトークンの選択範囲が広がっている。R-003 の記載と突き合わせる"
	fi

	# (c) 書き込みが拒否されること。**これがスコープの実効性を測る本体**である。
	#     読み取り側は公開リポジトリなら誰でも届くため、選択範囲の効果が見えない。
	#     権限を Contents: Write へ広げると 403 が 422（本文不備）へ変わるので、結果が実際に動く。
	#     本文を付けずに投げるので、仮に権限があっても**ファイルは作られない**（422 で弾かれる）。
	code="$(gh api -X PUT "repos/${WRITE_PROBE_REPO}/contents/.scope-probe" -i --silent 2>/dev/null | head -1)"
	case "$code" in
		*403*) ok "書き込みは拒否される（Contents: Write を渡していない）" ;;
		*422*) ng "書き込み権限があります（403 ではなく 422 が返りました。読み取り専用のはずです）" ;;
		*)     ng "書き込み可否を判定できません（応答: ${code:-なし}）" ;;
	esac
fi

head2 6/6 "品質ゲート（make audit-all / make test）"
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
