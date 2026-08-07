#!/usr/bin/env bash
# check-git-hooks.sh — git フックが「実際に作動する状態」にあるかを検査する（共通・スタック中立）。
#
# 【なぜ要るのか】
# 2026-08-07、sumai-desk で pre-push が**何のメッセージも出さずに走らない**状態が見つかった。
# 原因は install-hooks が絶対パスのシンボリックリンクを張っていたこと。devcontainer 内で
# 実行するとコンテナ内にしか無いパスを指すため、ホストのターミナルから push するとリンクが
# 解決できない。**git は解決できないシンボリックリンクを「フックが無い」と同じに扱う**ので、
# 警告も出さずに素通りする。落ちるより質が悪い——ゲートが在ると思ったまま1回も走らない。
#
# 【この検査の主眼は「リンクが相対であること」である】
# 存在・解決・実行権限だけを見ても意味がない。**監査を走らせる環境（＝devcontainer）では
# 絶対リンクも正しく解決するので常に緑**になり、今回のバグを1件も捕まえられない。
# 環境をまたいでも解決するための条件は相対リンクであることだけで、それは
# リポジトリが基盤の projects/ 配下にある限り成立する（ADR-010 の前提）。
#
# 【なぜレシピではなく結果を見るのか】
# install-hooks の実体は共通 contract.mk のほかに各プロジェクトの Makefile にもある
# （contract.mk を include すると overriding recipe 警告が出るため意図的に自前実装している）。
# Makefile を検査すると複製の数だけ漏れるが、**張られたリンクを見れば誰が張ったかに依存しない**。
#
# 【限界（承知のうえで単純にしている）】
# - CI ではフックを導入しないので判定しない。**最後の砦は CI 側**で、同じゲートを workflow が直接回す。
# - 誰も make audit を走らせなければ当然何も言わない。監査を回す動機そのものは仕組みで作れない。
#
# 使い方: check-git-hooks.sh <project-root>
# 終了コード: 0=問題なし / 1=問題あり / 2=呼び出し方の誤り（fail-closed）

set -u

# 検査対象のフック。install-hooks が張るものと一致させること。
HOOKS=(pre-push commit-msg)

die() { echo "  ❌ [git-hooks] $1" >&2; exit 2; }

fail=0
report() { echo "  ❌ $1"; fail=1; }

[ "$#" -eq 1 ] || die "使い方: check-git-hooks.sh <project-root>（fail-closed）"
ROOT="$1"
[ -d "$ROOT" ] || die "プロジェクトルートがありません: $ROOT"

# 共通側の実体の所在は、このスクリプト自身の位置から決める（common/scripts/ に置かれている前提）。
# 呼び出し側に階層の深さを仮定させない——`../../` の決め打ちは配置換えで静かに壊れる。
COMMON_SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# CI ではフックを導入しない。ここで赤にすると常時赤になり、すぐ無視されるようになる。
if [ -n "${CI:-}" ]; then
	echo "  ℹ CI ではフックを導入しないため未判定（ゲートは workflow が直接回します）"
	exit 0
fi

# 【自分自身がリポジトリのトップでなければ判定しない】
# ここを「git リポジトリか」だけで見ると2通りに誤る。
#   - new-service.sh の生成直後はまだ git init されていない。基盤の projects/ 配下に置くと
#     上方探索で**基盤リポの .git が見つかり、基盤側のフックを見て緑**になる（別のリポジトリの
#     結果で、そのプロジェクトを緑にしてしまう）。
#   - 単独チェックアウトでない複製（テスト用サンドボックス等）でも同じことが起きる。
# 自分のリポジトリを持たないなら、そもそも守るべき push ゲートが無い——飛ばすのが正しい。
# 黙って飛ばさず ℹ を出すのは、緑と未判定を読み手が区別できるようにするため。
toplevel="$(git -C "$ROOT" rev-parse --show-toplevel 2>/dev/null || true)"
root_abs="$(cd "$ROOT" && pwd -P)"
if [ -z "$toplevel" ]; then
	echo "  ℹ $ROOT は git リポジトリではないためフックは未判定（git init 後に判定対象になります）"
	exit 0
fi
if [ "$(cd "$toplevel" && pwd -P)" != "$root_abs" ]; then
	echo "  ℹ $ROOT は単独の git リポジトリではないためフックは未判定（上位リポジトリ側の監査が見ます）"
	exit 0
fi

# フックの置き場所を確定する。ここを間違えると**存在しないディレクトリを検査して緑になる**。
#   - worktree では --git-dir がワークツリー専用のディレクトリを返すが、git が読むのは共有側
#     （--git-common-dir）である。
#   - core.hooksPath が設定されていれば、git はそちらだけを見る（.git/hooks は無視される）。
#     見落とすと、空のディレクトリを指すだけでフックを全部無効化でき、しかも検査は緑のままになる。
hooks_dir="$(git -C "$ROOT" config --get core.hooksPath 2>/dev/null || true)"
if [ -n "$hooks_dir" ]; then
	# 相対指定は git の仕様どおりワークツリーのトップからの相対として解決する。
	case "$hooks_dir" in
		/*) [ -d "$hooks_dir" ] || hooks_dir="" ;;
		*)  hooks_dir="$(cd "$ROOT" && cd "$hooks_dir" 2>/dev/null && pwd)" || hooks_dir="" ;;
	esac
	if [ -z "$hooks_dir" ]; then
		report "core.hooksPath が解決できないディレクトリを指しています（フックは1本も走りません）"
		exit 1
	fi
else
	common_dir="$(git -C "$ROOT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
	[ -n "$common_dir" ] || die "フックディレクトリを特定できません（git 2.31 以降が要ります）"
	hooks_dir="$common_dir/hooks"
fi

for h in "${HOOKS[@]}"; do
	link="$hooks_dir/$h"
	want="$COMMON_SCRIPTS/$h"

	if [ ! -f "$want" ]; then
		report "$h: 共通側の実体がありません（$want）。参照先が消えています"
		continue
	fi
	if [ ! -L "$link" ] && [ ! -f "$link" ]; then
		report "$h: 導入されていません（make install-hooks を実行してください）"
		continue
	fi
	if [ ! -e "$link" ]; then
		report "$h: リンク先を解決できません（-> $(readlink "$link" 2>/dev/null)）。git はフックが無いものとして黙って素通りします"
		continue
	fi
	if [ ! -x "$link" ]; then
		report "$h: 実行権限がありません（git は実行可能でないフックを走らせません）"
		continue
	fi
	# ここが主眼。絶対リンクは「張った環境でだけ」解決するため、監査環境では緑のまま
	# ホストで素通りする。解決できる／できないに関わらず絶対なら赤にする。
	if [ -L "$link" ]; then
		tgt="$(readlink "$link")"
		case "$tgt" in
			/*) report "$h: リンクが絶対パスです（-> $tgt）。張った環境の外では解決できず、git が黙って素通りします。make install-hooks で張り直してください" ;;
		esac
	fi
	# すり替え検知。共通側の実体を指していること（別のスクリプトに差し替えられていないこと）。
	if [ "$(readlink -f "$link")" != "$(readlink -f "$want")" ]; then
		report "$h: 共通側の実体を指していません（-> $(readlink -f "$link")）。期待: $want"
	fi
done

[ "$fail" -eq 0 ] || exit 1
exit 0
