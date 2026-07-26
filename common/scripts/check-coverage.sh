#!/usr/bin/env bash
# check-coverage.sh <測定カバレッジ%> [リポジトリルート] — .coverage-floor と比較し、下回れば失敗する（一方向ラチェット）。
# 各スタックの `make coverage` から、計測したカバレッジ率(整数/小数)を引数で渡して呼ぶ。
# フロアは下げない運用：測定値がフロアを上回ったら .coverage-floor を手動で引き上げて後退を防ぐ。
# 詳細: docs/rules/quality-gates.md §5 / docs/rules/testing.md

set -u
# 検証対象リポジトリのルート。**第2引数**で受け取る（第1引数は測定カバレッジ値のため）。
# 省略時はスクリプト位置から導出＝従来動作。参照方式では共通リポの common/scripts/ から
# 各プロジェクトを検証するため、位置からの導出では正しいルートに解決できない。
# 引数を任意にしてあるのは既存の呼び出しを壊さないため（2026-07-26 フェーズ0）。
ROOT="${2:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
[ -d "$ROOT" ] || { echo "❌ 指定されたリポジトリルートが存在しません: $ROOT" >&2; exit 2; }
FLOOR_FILE="$ROOT/.coverage-floor"

measured="${1:-}"
if [ -z "$measured" ]; then
	echo "使い方: check-coverage.sh <測定カバレッジ%>" >&2
	exit 2
fi

floor="$(cat "$FLOOR_FILE" 2>/dev/null || echo 0)"
: "${floor:=0}"

# 数値バリデーション（fail-closed）。awk の `+0` は非数値を黙って 0 に丸めるため、
# 測定値・フロアが壊れているとゲートが無効化されたまま緑になる。それを防ぐ。
is_number() { printf '%s' "$1" | grep -qE '^[0-9]+(\.[0-9]+)?$'; }
if ! is_number "$measured"; then
	echo "❌ 測定カバレッジが数値ではありません: '$measured'" >&2
	exit 2
fi
if ! is_number "$floor"; then
	echo "❌ .coverage-floor の値が数値ではありません: '$floor'（ファイル破損の疑い）" >&2
	exit 2
fi

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
