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
#
# docs/decisions/（ADR）は走査対象から外す。ADR は意思決定の記録であり、「これから何を作るか」を
# 書く場所である。「結果」節に将来新設するファイルのパスが書かれるのは正常な状態で、そこへ実在検査を
# かけるのは ADR の性質と検査の目的が噛み合っていない。除外しないと ADR を起票するたびにリンク切れが
# 発生し、赤が常態化して他の赤に気づけなくなる（2026-08-03 の ADR-016・017 配置で実際に発生した）。
refs=$(grep -rhoE --exclude-dir=decisions 'docs/rules/[a-z0-9-]+\.md' CLAUDE.md docs/ 2>/dev/null | sort -u)
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
# （配布行の削除・退化を検出）。settings.json は安全機構（deny）の配布そのものであり、
# 退化すると新サービスがルール無しで生まれるため必ず含める。
# フック本体（guard-dangerous.sh / session-start-rules.sh）は 2026-08-04 に配布対象から外した
# （ADR-012 フェーズ2・案A）。複製を配ると `$CLAUDE_PROJECT_DIR` 依存のフック定義が各プロジェクトに
# 残り、サブディレクトリ起動で無警告に素通しする。実体はユーザースコープ1本に集約し、
# 配布経路は devcontainer のマウントが担う（検査(13)がマウントの実在を強制する）。
# ディレクトリ単位で配布されるもの（skills/agents/service-rules/decisions）は basename がディレクトリ名。
# 共通スクリプト（pre-push・commit-msg・check-*.sh）は配布対象から外した（ADR-010。参照で解決する）。
for req in \
	scripts/audit-consistency.sh \
	profiles/_base/Makefile profiles/_base/.github/workflows/ci.yml profiles/_base/.editorconfig profiles/_base/.coverage-floor \
	profiles/_base/.claude/settings.json profiles/_base/.claude/skills profiles/_base/.claude/agents \
	profiles/_base/.devcontainer/Dockerfile profiles/_base/.devcontainer/postCreate.sh profiles/_base/.devcontainer/devcontainer.json \
	profiles/_base/.devcontainer/init-firewall.sh \
	profiles/_base/gitignore.template profiles/_base/.env.example \
	profiles/_base/PROJECT.md.template profiles/_base/README.md.template \
	profiles/_base/docs/requirements \
	profiles/_base/.req-coverage-baseline profiles/_base/.tier-tripwire-allow \
	profiles/_base/docs/service-rules profiles/_base/docs/decisions \
	profiles/_base/.github/required-checks.txt \
	profiles/_base/scripts/verify-guardrails.md; do
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
		find .claude/skills .claude/agents -type f 2>/dev/null
		find profiles/_base/.claude/skills profiles/_base/.claude/agents -type f 2>/dev/null \
			| sed 's|^profiles/_base/||'
	} | sort -u
)
# フック本体は配布しない（2026-08-04・ADR-012 フェーズ2・案A）。実体はユーザースコープ1本で、
# 配布側に複製が**再び生えたら赤にする**。複製が生えると `$CLAUDE_PROJECT_DIR` 依存のフック定義も
# 一緒に戻り、サブディレクトリ起動で無警告に素通しする構成へ逆戻りするため。
for dead in profiles/_base/.claude/scripts service-templates/claude/scripts; do
	if [ -d "$ROOT/$dead" ] && [ -n "$(find "$ROOT/$dead" -type f 2>/dev/null)" ]; then
		report "配布側にフック複製が再発しています: $dead（ADR-012 フェーズ2でユーザースコープ1本に集約した）"
	fi
done
# settings.json は root にのみローカル固有キー（model/theme/通知フック等）があるため全文一致は課さず、
# 配布の本体である permissions ブロックのみを正規化（キー順・配列内順序を吸収）して比較する。
# 共通所有ファイルのロック deny（ADR-009: CLAUDE.md・docs/rules/ 等のサービス側編集禁止）は
# _base（配布側）にのみ置く。基盤リポ自身は共通所有ファイルの編集元なので root には置かない＝
# 比較時に _base 側から差し引いてから照合する（この配布分岐は意図的で、ここが差分の正の定義）。
#
# 正規化は**配列の値だけ**をソートする。permissions には配列以外のキーも入る
# （`defaultMode` は文字列。ADR-013 で追加）。無条件に sort を掛けると jq が
# 「string cannot be sorted」で異常終了し、diff の**両側が空になって「差分なし＝緑」**に
# なる——検査が無言で機能停止する（2026-08-04 の ADR-013 実装時に実測して判明）。
# 型を見てから畳むことで、スカラー値のキーが増えても検査が生き続ける。
if command -v jq >/dev/null 2>&1; then
	sort_arrays='with_entries(.value |= if type == "array" then sort else . end)'
	norm_perms=".permissions | $sort_arrays"
	common_lock_re='^(Write|Edit)\\((CLAUDE\\.md|docs/rules/.*|\\.claude/(settings\\.json|scripts/.*|skills/(extract-requirements|verify-request)/.*|agents/(consistency-auditor|security-reviewer)\\.md)|scripts/(pre-push|commit-msg|check-coverage\\.sh|check-requirements-coverage\\.sh|check-tier-tripwire\\.sh))\\)$'
	base_minus_lock=".permissions | .deny |= map(select(test(\"$common_lock_re\") | not)) | $sort_arrays"
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

# CI ゲートの退化検出。pre-push と CI の二重化（ADR-008「維持したもの」）は、片方から段が
# 消えても誰も気づかないまま成立しなくなる。実際 tier-tripwire ジョブが欠落していた（2026-07-25 是正）。
#
# 【2026-08-04 改訂・ADR-011】判定を「ジョブ名の直値一致」から「ゲートが実行されていること」へ変えた。
# 旧実装は `^  tier-tripwire:$` のようなジョブ名の一致で見ており、**改名・分割・reusable workflow への
# 移行のいずれでも壊れる**。この検査が守っている本質はジョブ名ではなく「6つのゲートが CI のどこかで
# 走ること」なので、そちらを直接見る。reusable 呼び出し形（common-gates / stack-gates に列挙する形）も
# 許容するため、将来サービス側の CI がどちらの形になっても検出力が落ちない。
# 基盤自身は reusable を呼ばない方針（ADR-011 注意事項）だが、検査は両方の形を受け付ける。
CI_YML="$ROOT/.github/workflows/ci.yml"
if [ -f "$CI_YML" ]; then
	# ゲート名:そのゲートが実行されたと判定できる正規表現（make 直呼び | reusable への受け渡し）
	CI_GATES=(
		"audit-all:(make[[:space:]]+audit-all|common-gates:.*audit-all)"
		"lint:(make[[:space:]]+lint|stack-gates:.*lint)"
		"test:(make[[:space:]]+test|stack-gates:.*test)"
		"req-coverage:(make[[:space:]]+req-coverage|common-gates:.*req-coverage)"
		"tier-tripwire:(make[[:space:]]+tier-tripwire|common-gates:.*tier-tripwire)"
		"secret-scan:(gitleaks)"
	)
	for entry in "${CI_GATES[@]}"; do
		gate="${entry%%:*}"; gate_re="${entry#*:}"
		if ! grep -qE "$gate_re" "$CI_YML"; then
			report ".github/workflows/ci.yml で必須ゲート '${gate}' が実行されていません（CI と pre-push の二重化が崩れます）"
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
	# ファイアウォール（ADR-013 第1層）: 同上。Dockerfile が COPY するため _base 側にも実体が要る。
	# 基盤リポ自身の .devcontainer にも複製が要る（docker の COPY はビルドコンテキストの外を読めない）
	"common/docker/init-firewall.sh:profiles/_base/.devcontainer/init-firewall.sh"
	"common/docker/init-firewall.sh:.devcontainer/init-firewall.sh"
	# 私的状態と共通資産の分離（ADR-013）: 同上。Dockerfile が COPY するため複製が要る。
	# 配布雛形（profiles/_base・service-templates・product-web）への展開は未実施（ADR-013「未解決」）
	"common/docker/setup-claude-config.sh:.devcontainer/setup-claude-config.sh"
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
# guard-shim.sh は 2026-08-04 に廃止した（ADR-012 決定3）ため、除外指定も撤去した。
#
# NEW_FORM: 参照方式へ**意図的に書き換えた**雛形。_base 側は旧方式のまま（new-service.sh が
# まだ _base を読むため）で、両者が一致しないのが正しい状態。追加時は理由を1行残すこと。
# フェーズ5で _base を撤去した時点でこの除外ごと消える。
# .github/required-checks.txt: _base は reusable 呼び出しへ移行し宣言が `ci / gates` の形になった。
# service-templates は旧方式（独立ジョブ）のまま残すので、一致しないのが正しい（2026-08-06・手順10）。
NEW_FORM_RE='^(Makefile|\.devcontainer/devcontainer\.json|\.github/workflows/ci\.yml|\.github/required-checks\.txt|claude/settings\.json)$'
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
done < <(cd "$ROOT/service-templates" 2>/dev/null && find . -type f ! -name 'README.md' | sed 's|^\./||' | sort)
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

echo "[audit] (13) 開発コンテナの隔離境界の退化検出（ADR-013 第1層）..."
# ADR-012 で「本物の境界はコンテナ隔離だけ」と決めた以上、境界を作る要素が Dockerfile から
# 落ちることは**防御そのものの消失**にあたる。しかも落ちても何も起きない（ビルドは通り、
# コンテナは動く）ため、人手のレビューでは検出できない。
#
# 特に危ないのが sudo の無制限化。`NOPASSWD:ALL` が復活すると、ファイアウォールを入れていても
# コンテナ内から `sudo iptables -F` で解除できてしまい、第1層が自己申告に落ちる。
#
# プロファイルの Dockerfile は「_base 全文 + 固有層」の約束だが、その一致を機械で見る仕組みが
# 無かった（2026-08-04 時点。検査(10)の対は common/ ↔ _base のみ）。全文一致は固有層があるため
# 課せないので、**境界を成す要素の実在**だけを個別に要求する。追加時は理由を1行残すこと。
FW_MARKERS=(
	"iptables ipset iproute2 dnsutils"                        # ファイアウォールの実行に要る道具
	"gpasswd -d node sudo"                                    # sudo グループ経由の昇格を塞ぐ
	"NOPASSWD: /usr/local/bin/init-firewall.sh"               # sudo はこの1本だけ
	"COPY init-firewall.sh /usr/local/bin/init-firewall.sh"   # 実行するのはイメージ内の root 所有コピー
)
FW_DOCKERFILES="
common/docker/Dockerfile.base
profiles/_base/.devcontainer/Dockerfile
service-templates/.devcontainer/Dockerfile
.devcontainer/Dockerfile
"
for df in $FW_DOCKERFILES "$ROOT"/profiles/*/files/.devcontainer/Dockerfile; do
	f="$df"; case "$df" in /*) ;; *) f="$ROOT/$df" ;; esac
	[ -f "$f" ] || continue
	rel="${f#"$ROOT"/}"
	for marker in "${FW_MARKERS[@]}"; do
		grep -qF "$marker" "$f" \
			|| report "隔離境界の退化: $rel に '$marker' がありません（ADR-013 第1層）"
	done
	# コメント行は除外する。Dockerfile 側は「NOPASSWD:ALL を残さない理由」を説明として
	# 書いており、それを退化と誤検出すると、正しい注記を消す方向へ人を誘導してしまう
	if grep -vE '^[[:space:]]*#' "$f" | grep -qE 'NOPASSWD:[[:space:]]*ALL'; then
		report "隔離境界の退化: $rel が sudo を無制限に許可しています（NOPASSWD:ALL。ADR-013 で1コマンドに絞った）"
	fi
done
# compose 方式のプロファイル（product-web）は devcontainer.json の runArgs が効かないため、
# NET_ADMIN / NET_RAW を compose 側で与える。落ちるとこのプロファイルだけ postStartCommand が
# 失敗し、waitFor によりコンテナが上がらない——他は動くので気づきにくい。
# bypassPermissions と MCP の ask はセットでしか成立しない。bypass は「明示的な ask ルール」だけは
# 素通りしない（公式ドキュメントで確認）ため、`ask` の `mcp__*` が MCP に対する唯一の実行時の歯止めに
# なる。片方だけ入ると、実行時に繋がった未知の MCP サーバーが無人で自動承認される。
# 設定ファイルの静的検査では未知サーバーの接続そのものは止められない——止めているのは ask ルールの方で、
# ここが検査しているのは「その歯止めが外れていないこと」である。
if command -v jq >/dev/null 2>&1; then
	for sf in "$ROOT/.claude/settings.json" "$ROOT/profiles/_base/.claude/settings.json" \
	          "$ROOT"/profiles/*/files/.claude/settings.json; do
		[ -f "$sf" ] || continue
		rel="${sf#"$ROOT"/}"
		[ "$(jq -r '.permissions.defaultMode // ""' "$sf")" = "bypassPermissions" ] || continue
		jq -e '.permissions.ask // [] | index("mcp__*")' "$sf" >/dev/null 2>&1 \
			|| report "隔離境界の退化: $rel は bypassPermissions なのに ask に 'mcp__*' がありません（MCP が無人で自動承認されます。ADR-013）"
	done
fi
for cf in "$ROOT"/profiles/*/files/.devcontainer/compose.yaml; do
	[ -f "$cf" ] || continue
	rel="${cf#"$ROOT"/}"
	for cap in NET_ADMIN NET_RAW; do
		grep -qF "$cap" "$cf" \
			|| report "隔離境界の退化: $rel に cap_add の $cap がありません（ファイアウォールが起動できません）"
	done
done
# 共通 .claude のユーザースコープ・マウント（ADR-012 フェーズ2で唯一の配布経路になった）。
# 生成プロジェクトは自前のフック定義もガード本体も持たず、**このマウント経由で共通側の
# settings.json（絶対パスのフック）と guard-dangerous.sh を受け取る**。ここが消えると、
# フックもルールも無いまま無警告で起動する——設定層では閉じられない穴なので第1層で検査する。
# compose 方式（product-web）は devcontainer.json の mounts が効かないため compose.yaml 側を見る。
for dj in "$ROOT/profiles/_base/.devcontainer/devcontainer.json" \
          "$ROOT/service-templates/.devcontainer/devcontainer.json" \
          "$ROOT"/profiles/*/files/.devcontainer/devcontainer.json; do
	[ -f "$dj" ] || continue
	rel="${dj#"$ROOT"/}"
	mount_src="$dj"
	# compose 方式なら同じディレクトリの compose.yaml が実際のマウント定義を持つ
	if grep -q '"dockerComposeFile"' "$dj" 2>/dev/null; then
		cf="$(dirname "$dj")/compose.yaml"
		[ -f "$cf" ] || { report "隔離境界の退化: $rel は compose 方式ですが compose.yaml がありません"; continue; }
		mount_src="$cf"
	fi
	grep -q '/home/node/\.claude' "$mount_src" \
		|| report "隔離境界の退化: ${mount_src#"$ROOT"/} が共通 .claude を /home/node/.claude へマウントしていません（フックもルールも配られなくなります。ADR-012）"
done

# 私的状態の逃がし先（ADR-013・2026-08-06）。共通 .claude は git 作業ツリーの bind なので、
# Claude Code の config ディレクトリをそこに置くと**認証情報が git 作業ツリーに入る**。
# さらに CLAUDE_CONFIG_DIR が無いと .claude.json が $HOME 直下（どのマウントにも無い）へ落ち、
# Rebuild のたびに再ログインになる。設定ファイルを読めば分かる退化なのでここで見る
# （実際に分離できているかの実測は verify-isolation.sh が担う）。
# 現時点の対象は基盤リポ自身のみ。配布雛形への展開は未実施（ADR-013「未解決」に記録）。
FOUNDATION_DEVCONTAINER="$ROOT/.devcontainer/devcontainer.json"
if [ ! -f "$FOUNDATION_DEVCONTAINER" ]; then
	report "隔離境界の退化: .devcontainer/devcontainer.json がありません"
else
	grep -q '"CLAUDE_CONFIG_DIR"[[:space:]]*:[[:space:]]*"/home/node/\.claude-state"' "$FOUNDATION_DEVCONTAINER" \
		|| report "隔離境界の退化: .devcontainer/devcontainer.json の containerEnv に CLAUDE_CONFIG_DIR=/home/node/.claude-state がありません（認証情報が git 作業ツリーへ戻り、.claude.json が Rebuild で消えます。ADR-013）"
	grep -q 'target=/home/node/\.claude-state,type=volume' "$FOUNDATION_DEVCONTAINER" \
		|| report "隔離境界の退化: .devcontainer/devcontainer.json が /home/node/.claude-state へ名前付きボリュームを貼っていません（Rebuild で認証情報が消えます。ADR-013）"
	# 呼び出し行そのものを見る。ファイル全体を grep するとコメント中の言及で緑になる。
	grep -q '"postStartCommand"[^"]*"[^"]*setup-claude-config\.sh' "$FOUNDATION_DEVCONTAINER" \
		|| report "隔離境界の退化: .devcontainer/devcontainer.json の postStartCommand が setup-claude-config.sh を呼んでいません（共通 deny・フック・agents・skills が config dir から見えなくなります。ADR-012／ADR-013）"
	grep -q 'COPY setup-claude-config\.sh' "$ROOT/.devcontainer/Dockerfile" \
		|| report "隔離境界の退化: .devcontainer/Dockerfile が setup-claude-config.sh を COPY していません（postStart が失敗してコンテナが準備完了になりません）"
	grep -q 'mkdir -p /home/node/\.claude-state' "$ROOT/.devcontainer/Dockerfile" \
		|| report "隔離境界の退化: .devcontainer/Dockerfile が /home/node/.claude-state を作っていません（名前付きボリュームが root 所有で初期化され、node が書けなくなります）"
fi

echo "[audit] (14) 二重化の突合（第2層 permissions.deny ↔ 第3層 PreToolUse フック）..."
# ADR-012 決定4: deny で表現できる判定は deny へ**追加**し、フックにも残す（二重化）。
# 冗長化の根拠は「片方が漏れるから」ではなく、**2つの層が独立に失敗する**こと——
# deny は例外を書けずに失敗し、フックは見つからずに失敗する。原因が共通していないため、
# simplicity-in-security（同一理由で壊れる重複は避ける）の例外にあたる。
#
# 逆に言えば、**片側だけが消えた瞬間に二重化は成立しなくなる**。しかも消えても何も起きない
# （テストは緑、コンテナは動く）。人手のレビューでは検出できないので機械で見る。
#
# 新しい正本ファイルは作らない。作ると「4箇所目の重複」になる（検査(7)が共通所有ロックで
# 採ったのと同じ判断）。フック側はマーカー、deny 側は settings.json から抜き出して突合する。
DUAL_LAYER=(
	# 判定ID:必須の deny ルール（フック側は `# @dual-layer: <ID>` のマーカーで対応づける）
	"A2:Bash(git push:*)"              # force push（push 全体を deny しているため --force も覆える）
	"A3:Bash(git reset *--hard*)"      # 履歴破棄。フラグ位置に依存しない形
	"A4:Bash(git clean -f*)"           # 作業ツリー破棄。-n/--dry-run は通す（例外はフック側が持つ）
	"A6:Bash(git checkout -- *)"       # パス指定による変更破棄
)
# 「1件でもあれば緑」では大半が消えても素通りするため、これが消えたら意味を失うものを個別に要求する
# （検査(7) の LOCK_CORE と同型。2026-08-04 追加）。追加時は理由を1行残すこと。
DENY_CORE=(
	"Bash(rm -rf:*)"          # 再帰強制削除の代表形
	"Bash(sudo rm:*)"         # sudo 経由の削除
	"Read(**/.env)"           # 秘密ファイルのツール経路（bash 経路はフックが担う）
	"Read(**/.ssh/**)"        # 秘密鍵
	"Read(**/.aws/**)"        # クラウド認証情報
)
GUARD_HOOK="$ROOT/.claude/scripts/guard-dangerous.sh"
if command -v jq >/dev/null 2>&1 && [ -f "$GUARD_HOOK" ]; then
	dual_settings=("$ROOT/.claude/settings.json" "$ROOT/profiles/_base/.claude/settings.json")
	for pset in "$ROOT"/profiles/*/files/.claude/settings.json; do
		[ -f "$pset" ] && dual_settings+=("$pset")
	done
	deny_has() { # <settings.json> <ルール文字列>
		jq -e --arg r "$2" '.permissions.deny // [] | index($r)' "$1" >/dev/null 2>&1
	}
	for entry in "${DUAL_LAYER[@]}"; do
		id="${entry%%:*}"; rule="${entry#*:}"
		# ① 第3層: フックに判定が残っていること
		grep -qE "^[[:space:]]*#[[:space:]]*@dual-layer:[[:space:]]*${id}([^0-9A-Za-z]|$)" "$GUARD_HOOK" \
			|| report "二重化の退化: フック $( basename "$GUARD_HOOK" ) に判定 $id のマーカーがありません（第3層から判定が消えた可能性。ADR-012 決定4）"
		# ② 第2層: 4本すべての deny に対応ルールがあること
		for sf in "${dual_settings[@]}"; do
			deny_has "$sf" "$rule" \
				|| report "二重化の退化: ${sf#"$ROOT"/} の deny に判定 $id の '$rule' がありません（第2層から判定が消えたか、4本の同期漏れ）"
		done
	done
	# ③ 逆方向: フックにマーカーがあるのに対応表に無い（実装だけ増えて突合が空回りするのを防ぐ）
	while IFS= read -r id; do
		[ -n "$id" ] || continue
		found=0
		for entry in "${DUAL_LAYER[@]}"; do [ "${entry%%:*}" = "$id" ] && found=1; done
		[ "$found" -eq 1 ] \
			|| report "二重化の突合漏れ: フックに @dual-layer: $id があるのに audit-consistency.sh の DUAL_LAYER に登録がありません"
	done < <(sed -n 's/^[[:space:]]*#[[:space:]]*@dual-layer:[[:space:]]*\([0-9A-Za-z]*\).*/\1/p' "$GUARD_HOOK" | sort -u)
	# ④ deny のコアが4本すべてに実在すること
	for core in "${DENY_CORE[@]}"; do
		for sf in "${dual_settings[@]}"; do
			deny_has "$sf" "$core" \
				|| report "deny コアの退化: ${sf#"$ROOT"/} の deny に '$core' がありません"
		done
	done
elif [ ! -f "$GUARD_HOOK" ]; then
	report "$GUARD_HOOK がありません（第3層の実体が消えています。ADR-012）"
fi

echo "[audit] (15) ワークフロー式の文脈検査（GitHub Actions）..."
# GitHub Actions は式で参照できる文脈が場所ごとに違う。**使えない文脈を書くとファイル全体が
# 「Invalid workflow file」になり、`on:` すら評価されないまま push に紐づいて0秒で失敗する**。
# 2026-08-04 に実際に発生した: `on: workflow_call` だけの service-ci.yml が、push のたびに
# 0秒で失敗していた。原因は step の `if:` で `secrets` を参照していたこと。
#
# ここで見るのは**実際に踏んだ1件だけ**にする。文脈の可用性表を丸ごと実装すると、
# 仕様変更で嘘をつくうえ、誤検出でワークフロー編集の邪魔になる（ゲートは踏んだ穴から育てる）。
# `secrets` は `with:` と job-level `env:` では使えるが、`if:` では使えない。
# 回避形は「job-level env で真偽値に落として、step は env を見る」。
for wf in "$ROOT"/.github/workflows/*.yml "$ROOT"/.github/actions/*/action.yml; do
	[ -f "$wf" ] || continue
	rel="${wf#"$ROOT"/}"
	if grep -nE '^[[:space:]]*if:.*secrets\.' "$wf" >/dev/null 2>&1; then
		report "ワークフロー式の文脈エラー: $rel の if: が secrets を参照しています（if: では使えません。job-level env に落としてから env を見ること。ファイル全体が Invalid workflow file になります）"
	fi
	# 踏んだ穴その2（2026-08-06 の selftest 実測）: skip されうるステップの出力をそのまま `token:` へ渡すと、
	# skip 時に**空文字**が入る。入力の既定値は「省いたとき」にしか効かないため、空文字は「未指定」ではなく
	# 「不正な指定」になり `Input required and not supplied: token` で落ちる。`||` で代替を書くこと。
	if grep -nE '^[[:space:]]*token:[[:space:]]*\$\{\{[[:space:]]*steps\.[A-Za-z0-9_-]+\.outputs\.[A-Za-z0-9_-]+[[:space:]]*\}\}' "$wf" >/dev/null 2>&1; then
		report "空になりうる token: $rel が skip されうるステップの出力を token へ直接渡しています（skip 時に空文字＝不正な指定になり checkout が落ちます。'|| github.token' 等の代替を書くこと）"
	fi
done

echo "[audit] (16) 必須ステータスチェック宣言の検査..."
# ブランチ保護の設定は GitHub 側にあり、ここからは見えない。**設定が正しいことは機械化できないが、
# 設定できる形になっていることは機械化できる**。実装は共通側に1本だけ置き、配布雛形からも同じものを
# 呼ぶ（ADR-010: 実体は1つ・参照する）。検査の中身と限界は check-required-checks.sh の冒頭に書いた。
bash "$ROOT/common/scripts/check-required-checks.sh" "$ROOT" || fail=1

echo "[audit] (17) 共通基盤の ref 二重記述の一致検査..."
# `uses: ...@X` と `foundation-ref: Y` がずれても**赤くならない**（ゲートは走って緑になり、
# 違うのは「どの版のゲートで検査したか」だけ）。症状の出ない食い違いなので機械で見る。
# 二重に書く羽目になった経緯は check-foundation-ref.sh の冒頭と計画書 §8-5。
bash "$ROOT/common/scripts/check-foundation-ref.sh" "$ROOT" || fail=1

echo ""
if [ "$fail" -ne 0 ]; then
	echo "[audit] ❌ 整合性監査で問題を検出しました。"
	exit 1
fi
echo "[audit] ✅ 整合性監査に問題はありません。"
