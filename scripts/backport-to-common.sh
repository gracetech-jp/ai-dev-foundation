#!/usr/bin/env bash
# backport-to-common.sh — 共通所有ファイルを共通リポジトリへ逆輸入（マニフェスト駆動）
#
# 各サービスに配布される標準ツール。`.backport-manifest` に列挙された「共通所有ファイル」だけを
# このサービスのワーキングツリーから共通リポへ上書き同期する（更新のみ・削除はしない）。
#
# 使い方（共通リポが見える環境で実行）:
#   ./scripts/backport-to-common.sh <共通リポのパス>                     # プレビュー（dry-run）
#   ./scripts/backport-to-common.sh <共通リポのパス> --apply             # 既存ファイルの更新のみ実行
#   ./scripts/backport-to-common.sh <共通リポのパス> --apply --allow-new # 共通リポに無いファイルの新規追加も許可
#   ./scripts/backport-to-common.sh <共通リポのパス> --apply --force     # 共通リポが dirty でも実行
#
# 安全機構:
#   - 既定では「共通リポに既に存在するファイルの更新のみ」。共通に無い新規ファイルは追加しない
#     （固有ルールの誤漏出を防ぐ）。意図的な新規追加は --allow-new を明示する＝レビューの合図。
#   - --apply 前に、共通リポの対象ファイルに未コミット変更があれば中断する（--force で回避）。
#     共通側の未コミット作業を盲目的な上書きで潰さないため。上書き前に自動バックアップも取る。
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
shift || true
APPLY=0; ALLOW_NEW=0; FORCE=0
for arg in "$@"; do
	case "$arg" in
		--apply) APPLY=1 ;;
		--allow-new) ALLOW_NEW=1 ;;
		--force) FORCE=1 ;;
		*) echo "不明なオプション: $arg" >&2; exit 1 ;;
	esac
done

if [ -z "$COMMON" ]; then
	echo "usage: $0 <共通リポのパス> [--apply] [--allow-new] [--force]" >&2; exit 1
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
	local entry
	while IFS= read -r entry || [ -n "$entry" ]; do
		entry="${entry%%#*}"                       # 行内コメント除去
		entry="$(echo "$entry" | xargs 2>/dev/null || true)"  # 前後空白除去
		[ -z "$entry" ] && continue
		if [ -d "$ROOT/$entry" ]; then             # ディレクトリ → 再帰
			(cd "$ROOT" && find "$entry" -type f)
		else                                       # ファイル or glob
			for f in "$ROOT"/$entry; do
				[ -f "$f" ] && echo "${f#"$ROOT"/}"
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

if [ "$APPLY" -ne 1 ]; then
	echo "== プレビュー（dry-run）。--apply で実際に上書きします。=="
	for rel in "${FILES[@]}"; do
		src="$ROOT/$rel"; dst="$COMMON/$rel"
		if [ ! -f "$dst" ]; then
			echo "  [新規] $rel  ※共通リポに無し。--allow-new を付けない限り追加されません（固有物の誤漏出防止）"
		elif ! diff -q "$src" "$dst" >/dev/null 2>&1; then
			echo "  [更新] $rel"
			diff -u "$dst" "$src" | sed 's/^/      /' || true
		else
			echo "  [同一] $rel"
		fi
	done
	echo ""
	echo "問題なければ:  $0 \"$COMMON\" --apply [--allow-new]"
	exit 0
fi

# --apply: 共通リポが git 管理下なら、対象ファイルに未コミット変更が無いか確認する
if git -C "$COMMON" rev-parse --git-dir >/dev/null 2>&1; then
	dirty="$( (cd "$COMMON" && git status --porcelain -- "${FILES[@]}") 2>/dev/null || true)"
	if [ -n "$dirty" ] && [ "$FORCE" -ne 1 ]; then
		echo "❌ 共通リポの対象ファイルに未コミットの変更があります。上書きで失われる恐れがあるため中断します。" >&2
		# shellcheck disable=SC2001  # 各行への固定プレフィックス付与は sed が最も明瞭
		echo "$dirty" | sed 's/^/      /' >&2
		echo "   先に共通リポ側で commit / stash してください（意図的に無視するなら --force）。" >&2
		exit 1
	fi
fi

BACKUP="$COMMON/.backport-backup-$(date +%Y%m%d-%H%M%S)"
echo "== 上書き実行。元ファイルは $BACKUP に退避します。=="
updated=0; added=0; skipped=0
for rel in "${FILES[@]}"; do
	src="$ROOT/$rel"; dst="$COMMON/$rel"
	if [ ! -f "$dst" ]; then
		if [ "$ALLOW_NEW" -ne 1 ]; then
			echo "  [skip] $rel（共通リポに無し・--allow-new 未指定）"
			skipped=$((skipped + 1)); continue
		fi
		mkdir -p "$(dirname "$dst")"; cp -a "$src" "$dst"
		echo "  [新規追加] $rel"; added=$((added + 1)); continue
	fi
	if diff -q "$src" "$dst" >/dev/null 2>&1; then
		continue  # 同一はスキップ（バックアップ不要）
	fi
	mkdir -p "$(dirname "$BACKUP/$rel")"; cp -a "$dst" "$BACKUP/$rel"
	cp -a "$src" "$dst"
	echo "  [更新] $rel"; updated=$((updated + 1))
done
echo ""
echo "完了: 更新 $updated 件 / 新規 $added 件 / スキップ $skipped 件"
[ "$skipped" -gt 0 ] && echo "  スキップした新規ファイルを追加するには --allow-new を付けて再実行してください。"
echo "共通リポで差分を確認してください:  (cd \"$COMMON\" && git status && git diff)"
