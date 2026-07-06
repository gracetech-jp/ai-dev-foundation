#!/usr/bin/env bash
# backport-to-common.sh — 共通所有ファイルを共通リポジトリへ逆輸入（マニフェスト駆動）
#
# 各サービスに配布される標準ツール。`.backport-manifest` に列挙された「共通所有ファイル」だけを
# このサービスのワーキングツリーから共通リポへ上書き同期する（追加/更新のみ・削除はしない）。
#
# 使い方（共通リポが見える環境で実行）:
#   ./scripts/backport-to-common.sh <共通リポのパス>           # プレビュー（dry-run）
#   ./scripts/backport-to-common.sh <共通リポのパス> --apply   # 実際に上書き（自動バックアップ）
#
# マニフェスト（.backport-manifest）の書式:
#   - 1行1エントリ。`#` 始まりと空行は無視。
#   - ファイル（例: CLAUDE.md）／ディレクトリ（末尾 / 、例: docs/rules/）／glob（例: .claude/skills/*/SKILL.md）を書ける。
#   - ディレクトリ配下は再帰的に全ファイルが対象。
#
# 規律: マニフェストに載せるファイルは「スタック中立（＝どのサービスでも通用する枠組み・原則）」に保つこと。
#       サービス固有の記述は SERVICE.md やマニフェスト対象外のファイルへ置く（詳細: docs/rules/backport.md）。

set -euo pipefail

# リポジトリルート（git 優先、無ければスクリプトの親ディレクトリ）
if ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"; then :; else
	ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi
MANIFEST="$ROOT/.backport-manifest"

COMMON="${1:-}"
MODE="${2:-}"

if [ -z "$COMMON" ]; then
	echo "usage: $0 <共通リポのパス> [--apply]" >&2; exit 1
fi
if [ ! -f "$MANIFEST" ]; then
	echo "マニフェストが見つかりません: $MANIFEST" >&2; exit 1
fi
if [ ! -d "$COMMON" ]; then
	echo "共通リポのパスがディレクトリではありません: $COMMON" >&2; exit 1
fi
COMMON="$(cd "$COMMON" && pwd)"

# マニフェスト → 対象ファイルの相対パス一覧へ展開
resolve_files() {
	local entry rel
	while IFS= read -r entry || [ -n "$entry" ]; do
		entry="${entry%%#*}"                       # 行内コメント除去
		entry="$(echo "$entry" | xargs 2>/dev/null || true)"  # 前後空白除去
		[ -z "$entry" ] && continue
		if [ -d "$ROOT/$entry" ]; then             # ディレクトリ → 再帰
			(cd "$ROOT" && find "$entry" -type f)
		else                                       # ファイル or glob
			for f in $ROOT/$entry; do
				[ -f "$f" ] && echo "${f#$ROOT/}"
			done
		fi
	done < "$MANIFEST" | sed 's|^\./||' | sort -u
}

mapfile -t FILES < <(resolve_files)

if [ "${#FILES[@]}" -eq 0 ]; then
	echo "マニフェストから対象ファイルを解決できませんでした。$MANIFEST を確認してください。" >&2; exit 1
fi

echo "== 逆輸入（このサービス → 共通リポ）=="
echo "  service : $ROOT"
echo "  common  : $COMMON"
echo "  対象     : ${#FILES[@]} 件（.backport-manifest 由来）"
echo ""

if [ "$MODE" != "--apply" ]; then
	echo "== プレビュー（dry-run）。--apply で実際に上書きします。=="
	for rel in "${FILES[@]}"; do
		src="$ROOT/$rel"; dst="$COMMON/$rel"
		if [ ! -f "$dst" ]; then
			echo "  [新規] $rel"
		elif ! diff -q "$src" "$dst" >/dev/null 2>&1; then
			echo "  [更新] $rel"
			diff -u "$dst" "$src" | sed 's/^/      /' || true
		else
			echo "  [同一] $rel"
		fi
	done
	echo ""
	echo "問題なければ:  $0 \"$COMMON\" --apply"
	exit 0
fi

BACKUP="$COMMON/.backport-backup-$(date +%Y%m%d-%H%M%S)"
echo "== 上書き実行。元ファイルは $BACKUP に退避します。=="
for rel in "${FILES[@]}"; do
	src="$ROOT/$rel"; dst="$COMMON/$rel"
	if [ -f "$dst" ]; then
		mkdir -p "$(dirname "$BACKUP/$rel")"; cp -a "$dst" "$BACKUP/$rel"
	fi
	mkdir -p "$(dirname "$dst")"; cp -a "$src" "$dst"
	echo "  ✅ $rel"
done
echo ""
echo "完了。共通リポで差分を確認してください:  (cd \"$COMMON\" && git status && git diff)"
