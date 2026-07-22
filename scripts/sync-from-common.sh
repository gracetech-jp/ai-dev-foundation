#!/usr/bin/env bash
# sync-from-common.sh — 共通リポの共通所有ファイルをこのサービスへ取り込む（順輸入・pull型）
#
# backport-to-common.sh（サービス → 共通）の対になる標準ツール。共通リポで改善・追加された
# 共通所有ファイルを、各サービスが自分のタイミングで取り込む。これで双方向ループが完成する:
#
#   共通リポ ──(new-service.sh で雛形展開)──▶ サービス
#      ▲│                                       │▲
#      │└──(sync-from-common.sh で取込)─────────┘│
#      └───(backport-to-common.sh で還流)◀───────┘
#
# 使い方（共通リポが見える環境で、サービス側から実行）:
#   ./scripts/sync-from-common.sh <共通リポのパス>            # プレビュー（dry-run）
#   ./scripts/sync-from-common.sh <共通リポのパス> --apply    # 更新・新規追加を適用
#   ./scripts/sync-from-common.sh <共通リポのパス> --apply --force  # サービス側が dirty でも実行
#
# 設計上の判断:
#   - マニフェストは【共通リポ側】の .backport-manifest を正とする。サービス側ローカルの
#     マニフェスト改変で取込範囲が歪むのを防ぐため（正本は1つ・ADR-003）。
#   - 新規ファイルは既定で追加する（逆輸入と非対称）。逆方向はサービス固有物の漏出リスクが
#     あるため --allow-new を要求するが、順方向の新規＝共通リポで生まれた新ルールであり、
#     配布することがこのツールの目的そのものだから。
#   - profiles/_base/ 由来の骨格（.claude/・.devcontainer/ 等）はマニフェスト対象外＝手動同期のまま
#     （パスが 1:1 対応しないため。docs/rules/backport.md 注1参照）。
#
# 安全機構:
#   - 既定は dry-run。--apply 前にサービス側の対象ファイルに未コミット変更があれば中断
#     （--force で回避）。サービス側の未コミット作業を盲目的な上書きで潰さないため。
#   - 上書き分は .sync-backup-*/ に自動退避する。
#   - コピーは一時ファイル + mv（アトミック差し替え）。実行中のこのスクリプト自身が
#     取込対象に含まれても、実行中プロセスを壊さないため。

set -euo pipefail

# リポジトリルート（git 優先、無ければスクリプトの親ディレクトリ）
if ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"; then :; else
	ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi

COMMON="${1:-}"
shift || true
APPLY=0; FORCE=0
for arg in "$@"; do
	case "$arg" in
		--apply) APPLY=1 ;;
		--force) FORCE=1 ;;
		*) echo "不明なオプション: $arg" >&2; exit 1 ;;
	esac
done

if [ -z "$COMMON" ]; then
	echo "usage: $0 <共通リポのパス> [--apply] [--force]" >&2; exit 1
fi
if [ ! -d "$COMMON" ]; then
	echo "共通リポのパスがディレクトリではありません: $COMMON" >&2; exit 1
fi
COMMON="$(cd "$COMMON" && pwd)"
MANIFEST="$COMMON/.backport-manifest"
if [ ! -f "$MANIFEST" ]; then
	echo "共通リポにマニフェストが見つかりません: $MANIFEST" >&2; exit 1
fi

# 共通リポ側マニフェスト → 共通リポ内の対象ファイル相対パス一覧へ展開
resolve_files() {
	local entry
	while IFS= read -r entry || [ -n "$entry" ]; do
		entry="${entry%%#*}"                             # 行内コメント除去
		entry="${entry#"${entry%%[![:space:]]*}"}"       # 先頭空白除去
		entry="${entry%"${entry##*[![:space:]]}"}"       # 末尾空白除去
		[ -z "$entry" ] && continue
		if [ -d "$COMMON/$entry" ]; then                 # ディレクトリ → 再帰
			(cd "$COMMON" && find "$entry" -type f)
		else                                             # ファイル or glob
			for f in "$COMMON"/$entry; do
				[ -f "$f" ] && echo "${f#"$COMMON"/}"
			done
		fi
	done < "$MANIFEST" | sed 's|^\./||' | sort -u
}

mapfile -t FILES < <(resolve_files)

if [ "${#FILES[@]}" -eq 0 ]; then
	echo "マニフェストから対象ファイルを解決できませんでした。$MANIFEST を確認してください。" >&2; exit 1
fi

echo "== 順輸入（共通リポ → このサービス）=="
echo "  common  : $COMMON"
echo "  service : $ROOT"
echo "  対象     : ${#FILES[@]} 件（共通リポ側 .backport-manifest 由来）"
echo ""

if [ "$APPLY" -ne 1 ]; then
	echo "== プレビュー（dry-run）。--apply で実際に取り込みます。=="
	for rel in "${FILES[@]}"; do
		src="$COMMON/$rel"; dst="$ROOT/$rel"
		if [ ! -f "$dst" ]; then
			echo "  [新規] $rel（共通リポで追加された共通所有ファイル。--apply で追加されます）"
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

# --apply: このサービスが git 管理下なら、対象ファイルに未コミット変更が無いか確認する
if git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
	dirty="$( (cd "$ROOT" && git status --porcelain -- "${FILES[@]}") 2>/dev/null || true)"
	if [ -n "$dirty" ] && [ "$FORCE" -ne 1 ]; then
		echo "❌ このサービスの対象ファイルに未コミットの変更があります。上書きで失われる恐れがあるため中断します。" >&2
		# shellcheck disable=SC2001  # 各行への固定プレフィックス付与は sed が最も明瞭
		echo "$dirty" | sed 's/^/      /' >&2
		echo "   先に commit / stash するか、共通へ還流すべき改善なら backport-to-common.sh を先に実行してください（意図的に無視するなら --force）。" >&2
		exit 1
	fi
fi

BACKUP="$ROOT/.sync-backup-$(date +%Y%m%d-%H%M%S)"
echo "== 取込実行。上書き分の元ファイルは $BACKUP に退避します。=="
updated=0; added=0
for rel in "${FILES[@]}"; do
	src="$COMMON/$rel"; dst="$ROOT/$rel"
	if [ -f "$dst" ] && diff -q "$src" "$dst" >/dev/null 2>&1; then
		continue  # 同一はスキップ（バックアップ不要）
	fi
	if [ -f "$dst" ]; then
		mkdir -p "$(dirname "$BACKUP/$rel")"; cp -a "$dst" "$BACKUP/$rel"
		echo "  [更新] $rel"; updated=$((updated + 1))
	else
		echo "  [新規追加] $rel"; added=$((added + 1))
	fi
	mkdir -p "$(dirname "$dst")"
	cp -a "$src" "$dst.sync-tmp.$$" && mv "$dst.sync-tmp.$$" "$dst"  # アトミック差し替え（自己上書き対策）
done
echo ""
echo "完了: 更新 $updated 件 / 新規 $added 件"
echo "このサービス側で差分を確認してください:  git status && git diff"
