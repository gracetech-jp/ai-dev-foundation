#!/usr/bin/env bash
# check-coverage.sh <測定カバレッジ%> — .coverage-floor と比較し、下回れば失敗する（一方向ラチェット）。
# 各スタックの `make coverage` から、計測したカバレッジ率(整数/小数)を引数で渡して呼ぶ。
# フロアは下げない運用：測定値がフロアを上回ったら .coverage-floor を手動で引き上げて後退を防ぐ。
# 詳細: docs/rules/quality-gates.md §5 / docs/rules/testing.md

set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FLOOR_FILE="$ROOT/.coverage-floor"

measured="${1:-}"
if [ -z "$measured" ]; then
	echo "使い方: check-coverage.sh <測定カバレッジ%>" >&2
	exit 2
fi

floor="$(cat "$FLOOR_FILE" 2>/dev/null || echo 0)"
: "${floor:=0}"

# 小数にも対応するため awk で数値比較する
if awk -v m="$measured" -v f="$floor" 'BEGIN { exit !((m + 0) < (f + 0)) }'; then
	{
		echo "❌ カバレッジ ${measured}% がフロア ${floor}% を下回りました（docs/rules/quality-gates.md §5）。"
		echo "   テストを追加してフロア以上にしてください。"
	} >&2
	exit 1
fi

echo "✅ カバレッジ ${measured}%（フロア ${floor}%）"
# ラチェット提案（自動では上げない。手動で .coverage-floor を更新する運用）
if awk -v m="$measured" -v f="$floor" 'BEGIN { exit !((m + 0) > (f + 0)) }'; then
	echo "↑ 提案: フロアを ${floor}% → ${measured}% に引き上げられます（.coverage-floor を更新）。"
fi
exit 0
