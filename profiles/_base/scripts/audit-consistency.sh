#!/usr/bin/env bash
# 整合性監査（サービス雛形）— docs/rules/consistency.md の「監査スクリプトの3層構成」に沿って
# 各サービスが中身を肉付けする。問題があれば非ゼロで終了する（pre-push / CI から呼ばれる）。

set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

fail=0
report() { echo "  ❌ $1"; fail=1; }

echo "[audit] (1) 軽量grep整合性..."
# TODO: 過去不具合の再発防止・層間の対応漏れ検出をここに追加する。

echo "[audit] (2) 構造的不変条件..."
# TODO: モデル/設定から導かれる「常に成り立つべき条件」を検証する。

echo "[audit] (3) スキーマdrift..."
# TODO: 実データモデルとマイグレーションのズレを検証する（実環境が必要）。

echo "[audit] (4) リネーム残渣スキャン（データ駆動）..."
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

echo "[audit] (5) CODEOWNERS 検査（要件パスのレビュー必須化。docs/rules/git.md）..."
# CODEOWNERS の存在と docs/requirements/ 所有者は必須（ファイル欠落は fail）。
if [ ! -f "$ROOT/.github/CODEOWNERS" ]; then
	report ".github/CODEOWNERS がありません（要件パスのレビュー必須化。docs/rules/git.md）"
elif ! grep -q 'docs/requirements/' "$ROOT/.github/CODEOWNERS"; then
	report ".github/CODEOWNERS に docs/requirements/ の所有者がありません（要件パスが未保護）"
fi
# サーバ側ブランチ保護の API 確認は行わない（solo・ブランチ保護未導入の間は認識済みの借金であり、
# 毎push の⚠警告が空回りしていたため 2026-07-23 に撤去）。フェーズ切替（開発者2人以上 or 初回リリース）で
# ブランチ保護を有効化する際、docs/rules/git.md のチェックリストに従い API 確認をここへ再追加する。

echo ""
if [ "$fail" -ne 0 ]; then
	echo "[audit] ❌ 整合性監査で問題を検出しました。"
	exit 1
fi
echo "[audit] ✅ 整合性監査に問題はありません。"
