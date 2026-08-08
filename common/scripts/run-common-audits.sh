#!/usr/bin/env bash
# run-common-audits.sh — 共通の整合性検査をまとめて実行する（共通・スタック中立）。
#
# 【解こうとしている問題: テンプレートドリフト】
# 共通検査の判定ロジックは既に common/scripts/ に1本ずつあるのに、**それを呼ぶ側**が
# 各リポジトリの audit-consistency.sh に複製されていた。基盤に検査を足しても、
# 呼び出しを書き足さない限りどのプロジェクトにも届かない。実際に2件（git フック・identity）が
# 届かないまま溜まり、grace-tech-hp では5件が欠落していた（調査: docs/audit/audit-script-drift-20260808.md）。
# **「基盤に検査を足したが、どこにも届いていない」は、作動していないゲートの配布版である。**
#
# ここに検査の一覧を集約し、プロジェクト側は**解決ボイラープレート＋1行の呼び出し**だけを持つ。
# 以後、共通検査を足すときはこのファイルに1行足せば、呼び出しを持つ全リポジトリへその場で届く。
#
# 【契約番号（第2引数）】
# 集約しても「呼び出しを持たないリポジトリ」「古い前提のまま呼んでいるリポジトリ」は残る。
# そこで**呼ぶ側に、自分が把握している検査集合の版を宣言させる**。ずれたら赤にする。
# 手口は check-foundation-ref.sh（`uses: ...@X` と `foundation-ref: Y` の一致を見る）と同じ——
# **二重に書かせて、食い違いを機械で検出する**。
#
# 検査を足して CONTRACT を上げると、宣言が古いリポジトリは赤になる。これは意図した挙動である。
# 新しい共通検査はプロジェクト側の準備（宣言ファイル等）を要することがあり、**黙って未判定に
# なるほうが害が大きい**。直し方は「新しい検査を確認して宣言の数字を上げる」だけで、
# 外部要因の赤（依存の脆弱性 DB 等）と違い、その場で閉じられる。
#
# 【この集約は CI 到達性の問題を解かない】
# 共通検査が CI で走るかどうかは、**そのリポジトリの CI が共通基盤を checkout するか**で決まる。
# reusable workflow（.github/workflows/service-ci.yml）は基盤を `path: .` へ checkout するので走るが、
# composite action だけを使うリポジトリでは基盤の木が無く、各検査は未判定になる。
# **「集約したから CI でも守られる」と読まないこと。** そちらは ADR-011 の reusable 移行が引き受ける。
#
# 使い方: run-common-audits.sh <project-root> <declared-contract>
# 終了コード: 0=全検査通過 / 1=1つ以上が赤（契約ずれを含む） / 2=呼び出し方の誤り（fail-closed）

set -u

# 共通検査の集合の版。**検査を追加・削除したら必ず上げること。**
# 上げ忘れると、呼ぶ側は古い宣言のまま緑になり、ドリフト検出が空回りする。
COMMON_AUDIT_CONTRACT=1

# 実行する検査。<スクリプト名>:<見出し> の順で並べる。ここに1行足すことが「配布」になる。
CHECKS=(
	"check-guardrail-duplication.sh:ガードレール二重化の突合（ADR-012 決定4）"
	"check-required-checks.sh:必須ステータスチェック宣言の検査"
	"check-foundation-ref.sh:共通基盤の ref 二重記述の一致検査"
	"check-git-hooks.sh:git フックが作動する状態にあること"
	"check-git-identity.sh:コミット identity のローカル上書き検出"
)

die() { echo "  ❌ [common-audits] $1" >&2; exit 2; }

fail=0

[ "$#" -eq 2 ] || die "使い方: run-common-audits.sh <project-root> <declared-contract>（fail-closed）"
ROOT="$1"
DECLARED="$2"
[ -d "$ROOT" ] || die "プロジェクトルートがありません: $ROOT"
printf '%s' "$DECLARED" | grep -qE '^[0-9]+$' \
	|| die "契約番号が数値ではありません: '$DECLARED'（呼び出し側が宣言する整数）"

# 自分の所在から共通スクリプト群の場所を決める（呼び出し側に階層を仮定させない）。
COMMON_SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "[common-audits] 共通監査 契約 v${COMMON_AUDIT_CONTRACT}（宣言 v${DECLARED}）— ${#CHECKS[@]}件"

# ── ドリフト検出 ──────────────────────────────────────────────────────────
if [ "$DECLARED" -lt "$COMMON_AUDIT_CONTRACT" ]; then
	echo "  ❌ 共通監査の契約がずれています（宣言 v${DECLARED} < 共通 v${COMMON_AUDIT_CONTRACT}）"
	echo "     共通側に検査が追加されています。**このリポジトリは新しい検査を把握していません。**"
	echo "     → 下に出る検査結果を確認し、必要な準備（宣言ファイル等）を済ませてから"
	echo "        audit-consistency.sh の呼び出しの数字を ${COMMON_AUDIT_CONTRACT} へ上げること"
	fail=1
elif [ "$DECLARED" -gt "$COMMON_AUDIT_CONTRACT" ]; then
	echo "  ❌ 共通監査の契約がずれています（宣言 v${DECLARED} > 共通 v${COMMON_AUDIT_CONTRACT}）"
	echo "     **参照している共通基盤のほうが古い。** checkout している ref を確認すること"
	echo "     （宣言だけ先に上げた場合もここに来る）"
	fail=1
fi

# ── 検査の実行 ────────────────────────────────────────────────────────────
# 1つ落ちても続ける。1回で全部の結果が出ないと、直すのに何往復もかかる（run-gates.sh と同じ方針）。
for spec in "${CHECKS[@]}"; do
	script="${spec%%:*}"
	title="${spec#*:}"
	path="$COMMON_SCRIPTS/$script"
	# 共通資産が欠けている状態を「検査なし」で素通しさせない。
	[ -r "$path" ] || die "$path が読めません（共通ゲートが壊れています）"
	echo "[common-audits] $title..."
	bash "$path" "$ROOT" || fail=1
done

[ "$fail" -eq 0 ] || exit 1
exit 0
