#!/usr/bin/env bash
# 整合性監査 — この基盤リポジトリ自身の整合性を機械的に検証する。
# ドキュメントのリンク切れ・make ターゲット漏れ・リネーム残渣を検出し、
# 問題があれば非ゼロで終了する（pre-push / CI から呼ばれる）。
#
# 枠組みは docs/rules/consistency.md の「監査スクリプトの3層構成」に準拠。
# この基盤リポジトリはアプリコードを持たないため、層(1) grep整合性を中心に実装する。

set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

fail=0
report() {
	# report <メッセージ>
	echo "  ❌ $1"
	fail=1
}

echo "[audit] (1) ドキュメントのリンク切れ検査..."
# CLAUDE.md および docs/rules 配下が参照する docs/rules/*.md が実在するか。
# 'xxx.md' は「詳細: docs/rules/xxx.md」形式の説明用プレースホルダなので除外する。
refs=$(grep -rhoE 'docs/rules/[a-z0-9-]+\.md' CLAUDE.md docs/ 2>/dev/null | sort -u)
for ref in $refs; do
	case "$ref" in
		docs/rules/xxx.md) continue ;;
	esac
	if [ ! -f "$ROOT/$ref" ]; then
		report "参照先が存在しない: $ref（参照元をgrepで確認）"
	fi
done

# docs/service-rules/ への参照。CLAUDE.md は共通配布されるため参照先の実体は各サービス側にあり、
# 基盤リポでは配布元 profiles/_base/docs/service-rules/ に存在すれば全サービスで解決する。
# どちらにも無ければ全サービスでリンク切れになるため fail とする。
refs_sr=$(grep -rhoE 'docs/service-rules/[a-z0-9-]+\.md' CLAUDE.md docs/ 2>/dev/null | sort -u)
for ref in $refs_sr; do
	if [ ! -f "$ROOT/$ref" ] && [ ! -f "$ROOT/profiles/_base/$ref" ]; then
		report "参照先が存在しない: $ref（root にも profiles/_base/ にも無し。全サービスでリンク切れになる）"
	fi
done

echo "[audit] (2) make ターゲット契約の検査..."
# quality-gates.md が要求する必須ターゲットが Makefile に定義されているか。
if [ ! -f "$ROOT/Makefile" ]; then
	report "Makefile が存在しない（quality-gates.md が make ターゲットを前提にしている）"
else
	for target in test lint coverage req-coverage tier-tripwire audit-all audit-deps install-hooks; do
		if ! grep -qE "^${target}:" "$ROOT/Makefile"; then
			report "Makefile に必須ターゲット '${target}:' が無い（docs/rules/quality-gates.md 参照）"
		fi
	done
fi

echo "[audit] (3) 新サービスへの配布漏れ検査..."
NS="scripts/new-service.sh"
# 共通ルール（CLAUDE.md・docs/rules/）は**配布してはならない**（2026-07-30 順輸入廃止・ADR-010）。
# 参照方式では実体は共通リポにのみ存在し、プロジェクトは上位探索で解決する。再び配り始めると
# 複製が生まれて乖離するため、cp 行の再発を検出する（コメント中の言及は拾わないよう cp 行に限定）。
if grep -nE '^[[:space:]]*cp[[:space:]].*(CLAUDE\.md|docs/rules/)' "$NS" >/dev/null; then
	report "new-service.sh が CLAUDE.md / docs/rules/ を配布しています（参照方式の退化。ADR-010 では配らない）"
fi
# 品質ゲート・Claudeガードレール・devcontainer一式が新サービスへ配布されているか
# （配布行の削除・退化を検出）。特に guard-dangerous.sh / settings.json / session-start-rules.sh は
# 安全機構の配布そのものであり、退化すると新サービスがガード無しで生まれるため必ず含める。
# ディレクトリ単位で配布されるもの（skills/agents/service-rules/decisions）は basename がディレクトリ名。
# 共通スクリプト（pre-push・commit-msg・check-*.sh）は配布対象から外した（ADR-010。参照で解決する）。
for req in \
	scripts/audit-consistency.sh \
	profiles/_base/Makefile profiles/_base/.github/workflows/ci.yml profiles/_base/.editorconfig profiles/_base/.coverage-floor \
	profiles/_base/.claude/settings.json profiles/_base/.claude/scripts/guard-dangerous.sh \
	profiles/_base/.claude/scripts/session-start-rules.sh profiles/_base/.claude/skills profiles/_base/.claude/agents \
	profiles/_base/.devcontainer/Dockerfile profiles/_base/.devcontainer/postCreate.sh profiles/_base/.devcontainer/devcontainer.json \
	profiles/_base/gitignore.template profiles/_base/.env.example \
	profiles/_base/PROJECT.md.template profiles/_base/README.md.template \
	profiles/_base/docs/requirements \
	profiles/_base/.req-coverage-baseline profiles/_base/.tier-tripwire-allow \
	profiles/_base/docs/service-rules profiles/_base/docs/decisions; do
	base="$(basename "$req")"
	if ! grep -q "$base" "$NS"; then
		report "new-service.sh が $base を新サービスへ配布していない（配布漏れ）"
	fi
done

# 要件トレーサビリティのターゲット/ジョブが配布雛形に存在するか（退化検出）。
# _base/Makefile は req-coverage / tier-tripwire を自前定義せず common/make/gates.mk から取り込む。
# 「ターゲット名がファイル中に現れるか」では**コメント中の言及でも緑になる**ため、include 行の実在で見る。
for needle in "common/make/contract.mk" "common/make/gates.mk"; do
	if ! grep -qE "^include .*$needle" "$ROOT/profiles/_base/Makefile"; then
		report "profiles/_base/Makefile が $needle を include していません（共通ゲートの取り込みが退化）"
	fi
done
for pair in "profiles/_base/.github/workflows/ci.yml:req-coverage" "profiles/_base/.github/workflows/ci.yml:tier-tripwire"; do
	tfile="${pair%%:*}"; needle="${pair##*:}"
	if [ -f "$ROOT/$tfile" ] && ! grep -q "$needle" "$ROOT/$tfile"; then
		report "$tfile に '$needle' がありません（要件トレーサビリティの配布退化）"
	fi
done

# 基盤リポ自身も CI 多段ゲートを持つ（dogfooding。削除・退化の検出）。
if [ ! -f "$ROOT/.github/workflows/ci.yml" ]; then
	report ".github/workflows/ci.yml が無い（基盤リポ自身のCIゲート。docs/rules/quality-gates.md §4）"
fi

echo "[audit] (4) リネーム残渣スキャン（データ駆動）..."
# 旧名→新名のリネームを行ったら、この配列に "旧名|新名" を1行追加する。
# 旧名がリポジトリ全域に残っていないかを検出する（誤検出回避のため除外パスを絞る）。
renames=(
	# 例: "oldFieldName|newFieldName"
	# 2026-07-30 サービス固有ルールのファイル名を SERVICE.md → PROJECT.md へ改名（互換読みは入れない）。
	# 走査は projects/ 配下の各プロジェクトにも及ぶため、そちらの追随が済むまでは赤が正しい。
	"SERVICE\.md|PROJECT.md"
)
# `[@]+...` は空配列+set -u で bash 4.3 以前が unbound エラーになるのを防ぐイディオム
for pair in ${renames[@]+"${renames[@]}"}; do
	old="${pair%%|*}"
	new="${pair##*|}"
	# .sync-backup-*/ は旧・順輸入が取っていた「同期前スナップショット」で、過去の姿を保存するのが役目。
	# 旧名が残っているのが正しいので残渣スキャンから外す（除外しないと恒久的な赤になる）。
	hits=$(grep -rn --exclude-dir=.git --exclude-dir=.claude --exclude-dir='.sync-backup-*' --exclude="audit-consistency.sh" -- "$old" "$ROOT" 2>/dev/null || true)
	if [ -n "$hits" ]; then
		report "リネーム残渣: 旧名 '$old'（→ '$new'）が残存:"
		# shellcheck disable=SC2001  # 各行への固定プレフィックス付与は sed が最も明瞭
		echo "$hits" | sed 's/^/       /'
	fi
done

echo "[audit] (5) Dockerfile の guard 依存(jq)の二重管理チェック..."
# guard-dangerous.sh は jq に依存する。root と profiles/_base の Dockerfile は別実体で手動同期のため、
# 片方だけ jq 導入が抜ける「サイレント退化」を検出する（全文一致は強制しない＝意図的分岐は許容）。
for df in .devcontainer/Dockerfile profiles/_base/.devcontainer/Dockerfile; do
	if [ ! -f "$ROOT/$df" ]; then
		report "$df が存在しない（devcontainer 設定）"
	elif ! grep -qE '(^|[[:space:]])jq([[:space:]]|$|\\)' "$ROOT/$df"; then
		report "$df が jq を導入していない（guard-dangerous.sh の依存。片側の退化の疑い）"
	fi
done
# プロファイルが Dockerfile を replace する場合、生成サービスの devcontainer はその Dockerfile になる。
# jq を欠くと配布先の guard がサイレントに壊れるため、プロファイル側 Dockerfile も同じ検査に含める（C-8 最小着手）。
for df in "$ROOT"/profiles/*/files/.devcontainer/Dockerfile; do
	[ -f "$df" ] || continue
	rel="${df#"$ROOT"/}"
	if ! grep -qE '(^|[[:space:]])jq([[:space:]]|$|\\)' "$df"; then
		report "$rel が jq を導入していない（guard-dangerous.sh の依存。プロファイル置換による退化）"
	fi
done

# （旧(6) CODEOWNERS 検査は 2026-07-24 の批准レス化（ADR-008）で撤去。要件パスの人間レビュー必須化
#   そのものを廃止したため。チーム化でレビュー運用を再導入する場合は ADR-008 を見直して復活させる）

echo "[audit] (6) 配布複製の同期検査（root ↔ profiles/_base）..."
# guard-dangerous.sh / session-start-rules.sh / skills / agents は root と profiles/_base の両方に複製配置され、
# 参照方式でもパスが 1:1 対応しないため手動同期（詳細: docs/rules/common-assets.md）。同期漏れは新規サービスだけが古いガードで生まれる
# 「サイレント分岐」になるため、複製ペアの diff 一致を機械強制する（2026-07-22 棚卸しで同期保証の空白として検出）。
# 基盤専用資産（root にのみ置き、意図的に配布しないもの）は片側欠落検査から除外する。
# 追加時は「配布しない」判断の日付・理由をここに1行残すこと。
FOUNDATION_ONLY=(
	".claude/skills/audit-ai-rules/"  # ルール監査は基盤で一括実施（2026-07-23 配布除外。docs/rules/common-assets.md）
)
is_foundation_only() {
	local p
	for p in "${FOUNDATION_ONLY[@]}"; do
		case "$1" in "$p"*) return 0 ;; esac
	done
	return 1
}
while IFS= read -r rel; do
	[ -n "$rel" ] || continue
	is_foundation_only "$rel" && continue
	if [ ! -f "$ROOT/$rel" ]; then
		report "配布複製の片側欠落: $rel が root 側に無い（profiles/_base のみ存在。手動同期漏れ）"
	elif [ ! -f "$ROOT/profiles/_base/$rel" ]; then
		report "配布複製の片側欠落: $rel が profiles/_base 側に無い（root のみ存在。手動同期漏れ）"
	elif ! diff -q "$ROOT/$rel" "$ROOT/profiles/_base/$rel" >/dev/null 2>&1; then
		report "配布複製が不一致: $rel（root ↔ profiles/_base の手動同期漏れ。diff で差分を確認して揃える）"
	fi
done < <(
	{
		find .claude/scripts .claude/skills .claude/agents -type f 2>/dev/null
		find profiles/_base/.claude/scripts profiles/_base/.claude/skills profiles/_base/.claude/agents -type f 2>/dev/null \
			| sed 's|^profiles/_base/||'
	} | sort -u
)
# settings.json は root にのみローカル固有キー（model/theme/通知フック等）があるため全文一致は課さず、
# 配布の本体である permissions ブロックのみを正規化（キー順・配列内順序を吸収）して比較する。
# 共通所有ファイルのロック deny（ADR-009: CLAUDE.md・docs/rules/ 等のサービス側編集禁止）は
# _base（配布側）にのみ置く。基盤リポ自身は共通所有ファイルの編集元なので root には置かない＝
# 比較時に _base 側から差し引いてから照合する（この配布分岐は意図的で、ここが差分の正の定義）。
if command -v jq >/dev/null 2>&1; then
	norm_perms='.permissions | with_entries(.value |= sort)'
	common_lock_re='^(Write|Edit)\\((CLAUDE\\.md|docs/rules/.*|\\.claude/(settings\\.json|scripts/.*|skills/(extract-requirements|verify-request)/.*|agents/(consistency-auditor|security-reviewer)\\.md)|scripts/(pre-push|commit-msg|check-coverage\\.sh|check-requirements-coverage\\.sh|check-tier-tripwire\\.sh))\\)$'
	base_minus_lock=".permissions | .deny |= map(select(test(\"$common_lock_re\") | not)) | with_entries(.value |= sort)"
	if ! diff -q \
		<(jq -S "$norm_perms" "$ROOT/.claude/settings.json") \
		<(jq -S "$base_minus_lock" "$ROOT/profiles/_base/.claude/settings.json") >/dev/null 2>&1; then
		report ".claude/settings.json の permissions が root ↔ profiles/_base で不一致（共通所有ロック deny 以外は同値必須。手動同期漏れ）"
	fi
	# ロック deny 自体の退化検出。「1件でもあれば緑」では大半が消えても素通りするため、
	# 仕組みの根を成すコア5点の実在を個別に要求する（2026-07-25 是正。旧実装は length>0 のみ）。
	# 挙げるのは「これが抜けたらロックの意味が失われる」ものに限る。追加時は理由を1行残すこと。
	LOCK_CORE=(
		"CLAUDE.md"                            # 共通ルールの本体
		"docs/rules/**"                        # 共通ルールの詳細
		".claude/settings.json"                # ロックの定義それ自体（自己防御）
		".claude/scripts/guard-dangerous.sh"   # bash 経路の遮断本体（自己防御）
		".claude/scripts/session-start-rules.sh"  # 共通ルールをセッションへ注入する本体（欠けると無言でルール無しになる）
	)
	# 検査するのは Edit のみ（2026-07-26）。Write はファイル権限チェックに一致せず効かない。
	for core in "${LOCK_CORE[@]}"; do
		if ! jq -e --arg e "Edit(${core})" '.permissions.deny | index($e)' \
			"$ROOT/profiles/_base/.claude/settings.json" >/dev/null 2>&1; then
			report "profiles/_base/.claude/settings.json の deny に 'Edit(${core})' がありません（ADR-009 ロックの退化）"
		fi
	done
	# プロファイル層の settings.json（ask のスタック別絞り込み。2026-07-23 導入）は
	# ask のみ _base と差分可。allow/deny/hooks の変更が _base に入ってもプロファイル複製に
	# 反映されず配布が分岐する事故を、ここで機械検出する（複製のトレードオフの機械的な塞ぎ）。
	for pset in "$ROOT"/profiles/*/files/.claude/settings.json; do
		[ -f "$pset" ] || continue
		if ! diff -q \
			<(jq -S 'del(.permissions.ask)' "$ROOT/profiles/_base/.claude/settings.json") \
			<(jq -S 'del(.permissions.ask)' "$pset") >/dev/null 2>&1; then
			report "プロファイル settings.json が _base と不一致（ask 以外の差分は禁止・手動同期漏れ）: ${pset#"$ROOT"/}"
		fi
	done
else
	report "jq が無く settings.json の permissions 同期検査ができません（guard-dangerous.sh も jq 依存。導入必須）"
fi

echo "[audit] (7) 共通所有ロックの定義突合（guard 正規表現 ↔ 配布 deny）..."
# 共通所有ファイルの定義が guard-dangerous.sh の COMMON_OWNED と配布 settings.json の deny に
# 分かれてハードコードされており、片方だけ更新すると穴が開く（2026-07-25 review 指摘）。
# 単一の正本を新設せず、機械的な突合で乖離を検出する方式を採る（正本化は配布経路の作り直しになるため）。
if command -v jq >/dev/null 2>&1; then
	GUARD=".claude/scripts/guard-dangerous.sh"
	BASE_SET="$ROOT/profiles/_base/.claude/settings.json"
	# ロックの実体は Edit(path) のみ（2026-07-26 是正）。
	# Claude Code は Write(path) をファイル権限チェックに一致させず、Edit(path) が全ファイル編集
	# ツールを覆う。旧実装は Write と Edit の対称性を必須にしていたが、片側は**効かないルール**で
	# あり、検査そのものが誤った前提に立っていた（セッション起動時に Claude Code が
	# 「Write(...) is not matched by file permission checks — only Edit(path) rules are」と
	# 警告することで判明）。Write 15件を削除し、Edit 一本に統一した。
	deny_edit() { jq -r '.permissions.deny[] | select(startswith("Edit(")) | ltrimstr("Edit(") | rtrimstr(")")' "$BASE_SET"; }
	# guard 側の正規表現はスクリプトから抜き出す（ここに書き写すと4箇所目の重複になるため）
	guard_re="$(sed -n "s/^[[:space:]]*COMMON_OWNED='\(.*\)'$/\1/p" "$ROOT/$GUARD")"
	if [ -z "$guard_re" ]; then
		report "$GUARD から COMMON_OWNED 正規表現を抽出できません（定義形式が変わった可能性。突合が空回りする）"
	else
		# ① deny の各パスが guard の正規表現に必ず掛かること（settings に足して guard を忘れた穴の検出）
		while IFS= read -r p; do
			[ -n "$p" ] || continue
			if ! printf '%s' "$p" | grep -qE "$guard_re"; then
				report "共通所有ロックの乖離: deny の '$p' が $GUARD の COMMON_OWNED に掛かりません（bash 経路が素通し）"
			fi
		done < <(deny_edit)
	fi
	# ② Write が残っていないこと。効かないルールを置くと「ロックされている」という誤解を生む。
	if jq -e '[.permissions.deny[] | select(startswith("Write("))] | length > 0' "$BASE_SET" >/dev/null 2>&1; then
		report "配布 settings.json に Write(...) の deny が残っています（ファイル権限チェックに一致せず無効。Edit(...) に一本化すること）"
	fi
	# ③ 旧「.backport-manifest の配布対象が全てロックされていること」は 2026-07-30 に撤去した。
	#    順輸入の廃止（ADR-010）でマニフェスト自体が無くなり、`[ -f ... ]` 付きのまま残すと
	#    **無言でスキップされる検査**になる（このリポジトリが繰り返し潰してきた失敗類型）。
	#    ロックの正本は guard の COMMON_OWNED と配布 deny の2つで、①がその一致を担保する。
fi

echo "[audit] (8) 基盤自身のゲート無効化検出..."
# 基盤リポは「アプリコードが無い」を理由にゲートを空設定にしがちだが、配布するガードレール自身が
# 基盤の機微面であり（R-001・R-002）、空設定＋機微面なし宣言では F2 も S4 も一度も走らない。
# 2026-07-24〜25 に実際にこの状態で緑になっていたため、機械検出する（ADR-008「維持したもの」の担保）。
empty_paths_re='^[[:space:]]*@?TIER_TRIPWIRE_PATHS=("")[[:space:]]'
if grep -qE "$empty_paths_re" "$ROOT/Makefile"; then
	report "Makefile の tier-tripwire が TIER_TRIPWIRE_PATHS 空で起動しています（基盤の機微面＝配布ガードレールが検査されません）"
fi
if [ -f "$ROOT/docs/requirements/.tier-tripwire-none" ]; then
	report "基盤リポに docs/requirements/.tier-tripwire-none があります（Tierトリップワイヤ全体が正当スキップされ無効化されます）"
fi

# CI ジョブの退化検出。pre-push と CI の二重化（ADR-008「維持したもの」）は、片方から段が
# 消えても誰も気づかないまま成立しなくなる。実際 tier-tripwire ジョブが欠落していた（2026-07-25 是正）。
CI_YML="$ROOT/.github/workflows/ci.yml"
if [ -f "$CI_YML" ]; then
	for job in audit lint test req-coverage tier-tripwire secret-scan; do
		if ! grep -qE "^[[:space:]]{2}${job}:[[:space:]]*$" "$CI_YML"; then
			report ".github/workflows/ci.yml に必須ジョブ '${job}' がありません（CI と pre-push の二重化が崩れます）"
		fi
	done
fi

echo "[audit] (9) 要件一覧（README）と要件ファイルの突合..."
# docs/requirements/README.md の一覧表は手書きのため実ファイルとずれる（R-001 の status が
# 長期間 draft のまま放置されていた。2026-07-25 是正）。ID と status の一致を機械強制する。
REQ_README="$ROOT/docs/requirements/README.md"
if [ -f "$REQ_README" ]; then
	for rf in "$ROOT"/docs/requirements/R-*.md; do
		[ -f "$rf" ] || continue
		rid="$(sed -n 's/^id:[[:space:]]*//p' "$rf" | head -1)"
		rstatus="$(sed -n 's/^status:[[:space:]]*//p' "$rf" | head -1)"
		[ -n "$rid" ] || continue
		row="$(grep -F "| $rid |" "$REQ_README" || true)"
		if [ -z "$row" ]; then
			report "要件一覧の漏れ: $rid が docs/requirements/README.md の表にありません"
		elif ! printf '%s' "$row" | grep -qF "$rstatus"; then
			report "要件一覧の乖離: $rid の status が README（表）と実ファイル（$rstatus）で不一致"
		fi
	done
fi

echo "[audit] (10) 参照にできない複製の同期検査（common/ ↔ service-templates/ ↔ actions/ ↔ _base/）..."
# 参照方式への移行で、共通資産の正本を common/ と service-templates/ へ移した。
# 順輸入の廃止（2026-07-30・ADR-010）でゲートスクリプトの旧パス複製は撤去できたが、
# 「参照にできない複製」だけが残る: composite action の同梱スクリプト（$GITHUB_ACTION_PATH から
# 読むため同梱が必須）と、new-service.sh が読む profiles/_base の Dockerfile。
# 放置すると「2箇所が別々に育って誰も気づかない」乖離になるため diff 一致を機械強制する。
# 追加時は「なぜこの対を持つのか」を1行残すこと。
MIGRATION_PAIRS=(
	# ゲートスクリプトの旧パス複製（scripts/check-*.sh・pre-push・commit-msg）は 2026-07-30 に削除した。
	# 順輸入の廃止（ADR-010）で「配布対象だから旧パスに実体を残す」理由が消え、正本は common/scripts/ の
	# 1箇所になった。Makefile・フック・CI はすべて common/ を参照する。
	# ベースイメージ: 正本は common/docker/。profiles/_base は new-service.sh が読むため残す
	"common/docker/Dockerfile.base:profiles/_base/.devcontainer/Dockerfile"
	# composite action の同梱スクリプト: 正本は common/scripts/（$GITHUB_ACTION_PATH から読むため同梱が必須）
	"common/scripts/check-requirements-coverage.sh:.github/actions/req-coverage/check-requirements-coverage.sh"
	"common/scripts/check-tier-tripwire.sh:.github/actions/tier-tripwire/check-tier-tripwire.sh"
	"common/scripts/check-coverage.sh:.github/actions/coverage-floor/check-coverage.sh"
)
for pair in "${MIGRATION_PAIRS[@]}"; do
	src="${pair%%:*}"; dst="${pair#*:}"
	if [ ! -f "$ROOT/$src" ]; then
		report "移行複製の正本が存在しない: $src（フェーズ0の構成が壊れています）"
	elif [ ! -f "$ROOT/$dst" ]; then
		report "移行複製の複製側が存在しない: $dst（正本 $src に対応する旧パスが消えています）"
	elif ! diff -q "$ROOT/$src" "$ROOT/$dst" >/dev/null 2>&1; then
		report "移行複製が不一致: $src ↔ $dst（片方だけ更新された。diff で確認して揃える）"
	fi
done
# service-templates/ ↔ profiles/_base/：service-templates/ が正本。.editorconfig と テンプレート5件は
# 「参照に変わるもの」として移送対象外のため、profiles/_base 側にのみ存在してよい。
#
# パス対応: service-templates/claude/... ↔ profiles/_base/.claude/...
# 先頭のドットを落としてあるのは、`.claude/skills/` というパスが作業ディレクトリ配下にあると
# Claude Code がそこをスコープ付きスキルとしてオンデマンドに読み込むため（実測）。
# 配布前の雛形が基盤セッションのスキル一覧に混ざるのを構造的に防ぐ（2026-07-26）。
# guard-shim.sh は新方式固有で _base に対応物が無いため対象外。
#
# NEW_FORM: 参照方式へ**意図的に書き換えた**雛形。_base 側は旧方式のまま（new-service.sh が
# まだ _base を読むため）で、両者が一致しないのが正しい状態。追加時は理由を1行残すこと。
# フェーズ5で _base を撤去した時点でこの除外ごと消える。
NEW_FORM_RE='^(Makefile|\.devcontainer/devcontainer\.json|\.github/workflows/ci\.yml|claude/settings\.json)$'
while IFS= read -r rel; do
	[ -n "$rel" ] || continue
	printf '%s' "$rel" | grep -qE "$NEW_FORM_RE" && continue
	base_rel="$rel"
	case "$rel" in claude/*) base_rel=".$rel" ;; esac
	if [ ! -f "$ROOT/profiles/_base/$base_rel" ]; then
		report "service-templates/$rel に対応する profiles/_base/$base_rel がありません（移行期は両方必要）"
	elif ! diff -q "$ROOT/service-templates/$rel" "$ROOT/profiles/_base/$base_rel" >/dev/null 2>&1; then
		report "移行複製が不一致: service-templates/$rel ↔ profiles/_base/$base_rel（片方だけ更新された）"
	fi
# README.md（このディレクトリ自身の説明＝所在の正本）は配布物ではないので対を要求しない。
# 配布される雛形は README.md.template のほうで、そちらは従来どおり一致を強制する。
done < <(cd "$ROOT/service-templates" 2>/dev/null && find . -type f ! -name 'guard-shim.sh' ! -name 'README.md' | sed 's|^\./||' | sort)
# マーカーの実在（全解決の起点。消えると Make も Docker も番人フックも解決不能になる）
[ -f "$ROOT/.ai-dev-foundation-root" ] || report "マーカー .ai-dev-foundation-root がありません（参照方式の全解決が失敗します）"

echo "[audit] (11) 参照方式の退化検出（共通スクリプトを複製前提のパスで案内していないか）..."
# ADR-010 以降、共通スクリプトの実体は common/scripts/ にしかない。ドキュメントや雛形が
# `scripts/pre-push` のようにプロジェクト直下を指す形で案内していると、読者は存在しないファイルを
# 探すことになる。2026-07-30 の移行で repo-layout.md の必須構成表と PROJECT.md.template に
# 実際に取り残しが出た（人手の grep では拾いきれなかった）ため、機械検出を常設する。
#
# 見るのは**バッククォートで囲まれたパス指定だけ**。settings.json の deny `Edit(scripts/pre-push)` は
# 「複製をプロジェクト側に作らせない」ためのロックであり、この表記のままが正しいので対象外。
# tests/ の bats はガードの入力としてこの文字列を意図的に使うため対象外。
# docs/decisions/・docs/audit/ は当時の記録なので対象外（過去を書き換えない）。
COMMON_SCRIPT_RE='pre-push|commit-msg|check-coverage\.sh|check-requirements-coverage\.sh|check-tier-tripwire\.sh'
while IFS= read -r hit; do
	[ -n "$hit" ] || continue
	report "参照方式の退化: $hit（共通スクリプトの実体は common/scripts/ のみ。common/ 付きで書くこと）"
done < <(grep -rnE "\`scripts/($COMMON_SCRIPT_RE)\`" \
	--include='*.md' --include='*.template' \
	"$ROOT/docs/rules" "$ROOT/profiles" "$ROOT/service-templates" "$ROOT/README.md" "$ROOT/CLAUDE.md" \
	2>/dev/null | sed "s|^$ROOT/||")

echo "[audit] (12) 所在の正本（各階層の README とツリー）の実在検査..."
# 「何がどこにあるか」は各階層の README が正本（docs/rules/repo-layout.md「所在の管理は…」）。
# README が無い／ツリーが無い状態を許すと、所在の記述がまたルール文書側へ散り、構成を変えるたびに
# N 文書を追う羽目になる（2026-07-30 の参照方式移行で9文書31箇所の追随が実際に発生した）。
# ツリーの実在は「自ディレクトリのパスだけの行」（例: `docs/rules/`）が存在するかで見る。
# 中身の正しさまでは機械で見ない——見られるのは「所在を書く場所がある」ことまで。
# 対象は**下位ディレクトリを案内する階層**だけ。ファイルが並ぶだけの階層には README を置かない
# （2026-07-30 ユーザー判断。1枚ずつ作ると作りすぎで、親のツリー1行で足りる）。
README_DIRS="common docs docs/decisions docs/requirements profiles service-templates"
for d in $README_DIRS; do
	# ディレクトリ自体が無ければ対象外（無いものの所在は書けない）。構成の欠落そのものは
	# 検査(3)の配布漏れ検査と Makefile の必須ターゲット検査が別途受け持つ。
	[ -d "$ROOT/$d" ] || continue
	f="$ROOT/$d/README.md"
	if [ ! -f "$f" ]; then
		report "$d/README.md がありません（所在の正本。docs/rules/repo-layout.md）"
	elif ! grep -qxF "$d/" "$f"; then
		report "$d/README.md に自ディレクトリのツリーがありません（'$d/' の行で始まるツリーを置くこと）"
	fi
done
grep -qxF "ai-dev-foundation/" "$ROOT/README.md" 2>/dev/null \
	|| report "README.md にリポジトリ直下のツリーがありません（'ai-dev-foundation/' の行で始まるツリー）"

echo ""
if [ "$fail" -ne 0 ]; then
	echo "[audit] ❌ 整合性監査で問題を検出しました。"
	exit 1
fi
echo "[audit] ✅ 整合性監査に問題はありません。"
