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
# 共通資産（deny・フック・agents・skills）の配布先。ADR-012 フェーズ2で唯一の経路になった。
# 実体は基盤リポの .claude＝git 作業ツリーなので、認証情報はここへ置かない（ADR-013）。
COMMON_CLAUDE_DIR="/home/node/.claude"
BLOCKED_URL="https://example.com"
ALLOWED_URL="https://api.anthropic.com"

# GH_TOKEN に許可したリポジトリ（R-003「GitHub へ渡す資格情報のスコープ」の正本と一致させる）。
# ここが増えたら爆発半径が広がっているので、値だけ直して済ませず R-003 側も更新すること。
ALLOWED_REPOS=(
	"gracetech-jp/ai-dev-foundation"
	"gracetech-jp/grace-tech-hp"
	"gracetech-jp/sumai-desk"
)
# スコープを測る先。**存在するリポジトリでなければならない**（不在なら 404 で、
# 権限不足の 403 と区別できない）。
WRITE_PROBE_REPO="gracetech-jp/ai-dev-foundation"

pass=0
fail=0

ok()   { echo "  ✅ $1"; pass=$((pass + 1)); }
ng()   { echo "  ❌ $1"; fail=$((fail + 1)); }
head2() { echo ""; echo "[$1] $2"; }

head2 1/7 "init-firewall.sh が実際に走ったか"
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

head2 2/7 "既定ポリシーが DROP になっているか"
# 非 root ではポリシーを読めないため、スクリプトが記録した適用内容で確認する。
# 実際の振る舞いは 3/5 が受け持つ（記録と実測の両方が揃って初めて信頼できる）。
if [ -f "$STATUS_FILE" ] && grep -q 'policy=DROP' "$STATUS_FILE"; then
	ok "既定ポリシー DROP を適用した記録がある"
else
	ng "DROP を適用した記録がない（1/5 が失敗しているならそちらが原因）"
fi

head2 3/7 "許可リスト外への通信が実際に遮断されるか"
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

head2 4/7 "sudo が init-firewall.sh 以外で使えないこと"
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

head2 5/7 "GH_TOKEN のスコープが実際に効いているか"
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

	# (c) 記録どおり**書き込める**こと（2026-08-06 に Contents を Read and write へ広げた。
	#     コンテナから push するため。R-003「GitHub へ渡す資格情報のスコープ」が正本）。
	#     ここは実効性の検査ではなく**記録と実態の一致**を見る検査になった——
	#     読み取り専用へ戻ったのに R-003 が書き込み可のままなら、記録のほうが嘘になる。
	#     本文を付けずに投げるため、権限があっても**ファイルは作られない**（本文検証で落ちる）。
	#     実測（2026-08-06）: 権限あり → 400 / 読み取り専用 → 403。認可は本文検証より先に効く。
	code="$(gh api -X PUT "repos/${WRITE_PROBE_REPO}/contents/.scope-probe" -i --silent 2>/dev/null | head -1)"
	case "$code" in
		*400*|*422*) ok "書き込み権限がある（Contents: Read and write。R-003 の記載どおり）" ;;
		*403*)       ng "書き込みが拒否されました（R-003 は Read and write と記録しています。実態と記録が食い違っています）" ;;
		*)           ng "書き込み可否を判定できません（応答: ${code:-なし}）" ;;
	esac

	# (d) **渡していない権限が本当に無いこと。** (c) が「書けること」を見る検査に変わった以上、
	#     上限を測る検査が別に要る（でないと「全部渡しても緑」になる）。
	#     ブランチ保護 API は Administration を要求する。未付与なら 403、付与されていれば
	#     200（保護あり）か 404（保護なし）になり、**スコープを広げたら結果が変わる**。
	code="$(gh api "repos/${WRITE_PROBE_REPO}/branches/main/protection" -i --silent 2>/dev/null | head -1)"
	case "$code" in
		*403*) ok "リポジトリ設定の変更 API は拒否される（Administration を渡していない）" ;;
		*)     ng "Administration を渡している可能性があります（403 ではなく ${code:-なし}）。R-003 の記載と突き合わせる" ;;
	esac
fi

head2 6/7 "認証情報が git 作業ツリーの外に置かれ、Rebuild をまたいで残るか"
# ADR-013（2026-08-06）。Claude Code は認証情報と .claude.json を config ディレクトリへ書く。
# 共通 .claude は基盤リポの bind＝git 作業ツリーなので、そこを config ディレクトリにすると
# 認証情報が作業ツリーに入る。設定ファイルが正しいことは audit の検査(13)が見るので、
# ここは**実際に分離できているか**を測る。
if [ -z "${CLAUDE_CONFIG_DIR:-}" ]; then
	ng "CLAUDE_CONFIG_DIR が未設定です（.claude.json が \$HOME 直下に落ち、Rebuild で消えます）"
	echo "     → devcontainer.json の containerEnv を確認し、Rebuild する"
elif [ "$CLAUDE_CONFIG_DIR" = "$COMMON_CLAUDE_DIR" ]; then
	ng "CLAUDE_CONFIG_DIR が共通 .claude と同じです（認証情報が git 作業ツリーに入ります）"
else
	ok "config ディレクトリは共通 .claude と別（$CLAUDE_CONFIG_DIR）"

	# overlay 上ではなく独立したマウントであること。ここが「Rebuild をまたいで残る」の実体で、
	# 今回の不具合（$HOME/.claude.json が overlay 上にあった）とちょうど同じ形を検出する。
	if [ "$(findmnt -no TARGET --target "$CLAUDE_CONFIG_DIR" 2>/dev/null)" = "$CLAUDE_CONFIG_DIR" ]; then
		ok "$CLAUDE_CONFIG_DIR は独立したマウント（Rebuild をまたいで残る）"
	else
		ng "$CLAUDE_CONFIG_DIR がマウントされていません（コンテナの overlay 上＝Rebuild で消えます）"
	fi

	# 認証まわりの実体が config ディレクトリ側にあること。
	for f in .credentials.json .claude.json; do
		if [ -f "$CLAUDE_CONFIG_DIR/$f" ]; then
			ok "$f が config ディレクトリ側にある"
		else
			ng "$CLAUDE_CONFIG_DIR/$f がありません（$f が別の場所に書かれています）"
		fi
	done

	# 逆に、git 作業ツリー側と $HOME 直下には残っていないこと。
	leftover=""
	[ -e "$COMMON_CLAUDE_DIR/.credentials.json" ] && leftover="$leftover $COMMON_CLAUDE_DIR/.credentials.json"
	[ -e "$HOME/.claude.json" ] && leftover="$leftover $HOME/.claude.json"
	if [ -z "$leftover" ]; then
		ok "git 作業ツリーと \$HOME 直下に認証情報が残っていない"
	else
		ng "認証情報が古い場所に残っています:$leftover"
		echo "     → 移設済みなら手動で削除する（setup-claude-config.sh は移設元を消さない）"
	fi

	# 共通資産（ADR-012 の配布経路）が config ディレクトリから見えること。
	# CLAUDE_CONFIG_DIR を設定すると settings.json の読み取り元もそこへ移るため、
	# symlink が切れると**共通 deny もフックも読まれないまま**起動する。
	for name in settings.json skills agents; do
		if [ ! -L "$CLAUDE_CONFIG_DIR/$name" ]; then
			ng "$CLAUDE_CONFIG_DIR/$name が symlink ではありません（共通資産が配られていません。ADR-012）"
		elif [ "$(readlink -f "$CLAUDE_CONFIG_DIR/$name")" = "$(readlink -f "$COMMON_CLAUDE_DIR/$name")" ]; then
			ok "$name は共通側を指している"
		else
			ng "$CLAUDE_CONFIG_DIR/$name の指す先が共通側ではありません（$(readlink "$CLAUDE_CONFIG_DIR/$name")）"
		fi
	done
fi

head2 7/7 "品質ゲート（make audit-all / make test）"
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
