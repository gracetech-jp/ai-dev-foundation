#!/usr/bin/env bash
# 整合性監査（サービス雛形）— docs/rules/consistency.md の「監査スクリプトの3層構成」に沿って
# 各サービスが中身を肉付けする。問題があれば非ゼロで終了する（pre-push / CI から呼ばれる）。

set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

fail=0
report() { echo "  ❌ $1"; fail=1; }

# ── 前半: 共通監査（実体は共通基盤に1本。ここは呼ぶだけ）────────────────────
# 共通検査の一覧と判定は common/scripts/run-common-audits.sh が持つ。**番号を振らない**のが
# 要点で、共通側に検査が増えても下の (P1..) と衝突しない（共通と固有が同じ番号空間を
# 共有していたのが衝突の元だった）。第2引数はこのリポジトリが把握している検査集合の版で、
# 共通側が進むと赤になる（ドリフト検出。詳細は run-common-audits.sh の冒頭）。
# 解決できないときは黙って飛ばさず理由を出す（無言のスキップは「作動していないゲート」になる）。
ca_dir="$ROOT"
ca_root=""
while [ "$ca_dir" != "/" ]; do
	if [ -f "$ca_dir/.ai-dev-foundation-root" ]; then
		ca_root="$ca_dir"
		break
	fi
	ca_dir="$(dirname "$ca_dir")"
done
ca_script="${ca_root:+$ca_root/common/scripts/run-common-audits.sh}"
if [ -z "$ca_root" ]; then
	echo "  ℹ 共通基盤が見つからないため共通監査はスキップしました（CI の単独チェックアウト等）"
elif [ ! -r "$ca_script" ]; then
	report "共通基盤は見つかりましたが $ca_script が読めません（共通ゲートが配られていません）"
else
	bash "$ca_script" "$ROOT" 1 || fail=1
fi
echo ""

# ── 後半: このサービス固有の検査（P = project）────────────────────────────
# 番号は共通側と分けてある。共通監査に検査が増えても、ここを振り直す必要はない。
echo "[audit] (P1) 軽量grep整合性..."
# TODO: 過去不具合の再発防止・層間の対応漏れ検出をここに追加する。

echo "[audit] (P2) 構造的不変条件..."
# TODO: モデル/設定から導かれる「常に成り立つべき条件」を検証する。

echo "[audit] (P3) スキーマdrift..."
# TODO: 実データモデルとマイグレーションのズレを検証する（実環境が必要）。

echo "[audit] (P4) リネーム残渣スキャン（データ駆動）..."
# 旧名→新名のリネームを行ったら "旧名|新名" を1行追加する。
renames=(
	# 例: "oldFieldName|newFieldName"
)
# `[@]+...` は空配列+set -u で bash 4.3 以前が unbound エラーになるのを防ぐイディオム
for pair in ${renames[@]+"${renames[@]}"}; do
	old="${pair%%|*}"; new="${pair##*|}"
	hits=$(grep -rn --exclude-dir=.git --exclude-dir=node_modules --exclude="audit-consistency.sh" -- "$old" "$ROOT" 2>/dev/null || true)
	if [ -n "$hits" ]; then
		report "リネーム残渣: 旧名 '$old'（→ '$new'）が残存:"
		# shellcheck disable=SC2001  # 各行への固定プレフィックス付与は sed が最も明瞭
		echo "$hits" | sed 's/^/       /'
	fi
done

# （旧(5) CODEOWNERS 検査は 2026-07-24 の批准レス化（ADR-008）で撤去。要件パスの人間レビュー必須化
#   そのものを廃止したため。チーム化でレビュー運用を再導入する場合は ADR-008 を見直して復活させる）

echo ""
if [ "$fail" -ne 0 ]; then
	echo "[audit] ❌ 整合性監査で問題を検出しました。"
	exit 1
fi
echo "[audit] ✅ 整合性監査に問題はありません。"
