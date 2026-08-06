#!/usr/bin/env bash
# Claude Code の「私的状態」と「共通資産」を別々の入れ物に分ける（ADR-013 / ADR-012）。
# postStartCommand から node 権限で走る。root は要らない。
#
# 【解こうとしている問題】
# Claude Code は認証情報（.credentials.json）とアカウント情報（.claude.json）を
# **config ディレクトリ**へ書く。一方 /home/node/.claude は ADR-012 フェーズ2で
# 「共通 deny・フック・agents・skills の唯一の配布経路」になっており、その実体は
# 基盤リポの .claude——git 作業ツリーの中である。両者が同じディレクトリだと、
# 認証情報が git 作業ツリーに置かれる。
# さらに .claude.json は既定では config ディレクトリではなく $HOME 直下に落ちる。
# $HOME はどのマウントにも含まれないため、**Rebuild のたびに消えてログインし直しになる**
# （2026-08-06 の実測: numStartups=1 / firstStartTime=コンテナ起動時刻）。
#
# 【採った構成】
#   CLAUDE_CONFIG_DIR = /home/node/.claude-state   名前付きボリューム。私的状態はすべてここ
#   /home/node/.claude                             基盤リポの .claude を bind。共通資産の配布経路
#   config dir 内の settings.json / skills / agents を共通側への symlink にする
#
# 【なぜ symlink が要るのか（2026-08-06 実測）】
# CLAUDE_CONFIG_DIR を設定すると、ユーザースコープ settings.json の**読み取り元もそこへ移る**。
# config dir に置いた SessionStart フックだけが発火し、$HOME/.claude に置いたフックは
# 発火しなかった。つまり config dir と配布経路は独立していない。したがって
# 「ボリュームへ向けるだけで symlink 不要」という変種は成立せず、config dir 側から共通側を指す。
# CLAUDE_CODE_MANAGED_SETTINGS_PATH で共通側を配る案も試したが、2.1.223 では honored されなかった
# （フックが発火しない）ため採らない。
#
# scripts/ を symlink しないのは、フック定義が /home/node/.claude/scripts/... という
# **絶対パス**で書かれており、config dir の位置に依存しないため。
set -euo pipefail

COMMON_DIR="/home/node/.claude"
STATE_DIR="${CLAUDE_CONFIG_DIR:-}"

die() { echo "[claude-config] エラー: $*" >&2; exit 1; }

# fail-closed。ここで黙って続けると、共通 deny もフックも読まれないまま
# bypassPermissions のコンテナが起動する（設定層では閉じられない穴）。
[ -n "$STATE_DIR" ] \
	|| die "CLAUDE_CONFIG_DIR が未設定です（devcontainer.json の containerEnv を確認）"
[ "$STATE_DIR" != "$COMMON_DIR" ] \
	|| die "CLAUDE_CONFIG_DIR が共通 .claude と同じです（認証情報が git 作業ツリーに入ります）"
[ -d "$COMMON_DIR" ] \
	|| die "$COMMON_DIR がありません（共通 .claude のマウントが消えています。ADR-012 の配布経路）"
[ -d "$STATE_DIR" ] \
	|| die "$STATE_DIR がありません（名前付きボリュームのマウントが消えています）"
[ -w "$STATE_DIR" ] \
	|| die "$STATE_DIR へ書き込めません（ボリュームが root 所有で作られた可能性。Dockerfile の mkdir を確認）"

# 共通資産を config dir から見えるようにする。実体は共通側にしか置かない（参照方式・ADR-010）。
link_common() {
	local name="$1" src="$COMMON_DIR/$1" dst="$STATE_DIR/$1"
	[ -e "$src" ] || die "$src がありません（共通資産の配布経路が壊れています）"
	if [ -L "$dst" ] || [ -f "$dst" ]; then
		# 実体ファイルに化けているのは、Claude Code が settings.json を書き戻した跡
		# （/config のテーマ変更などで起きる）。毎回張り直すことで自己修復させる。
		rm -f "$dst"
	elif [ -e "$dst" ]; then
		die "$dst が実体のディレクトリとして存在します。退避してから起動し直してください"
	fi
	ln -s "$src" "$dst"
}
for name in settings.json skills agents; do
	link_common "$name"
done

# 【一度きりの移設】config dir を分ける前は、私的状態が共通側（＝git 作業ツリー）に溜まっていた。
# 認証情報が向こうにあるうちは持ってくる。持ってこないと、この変更の初回 Rebuild だけ
# ログインし直しになり、過去のセッション（--resume）も見えなくなる。
# 移設元は**消さない**（削除は人が確認してから行う。CLAUDE.md の制約）。
if [ ! -e "$STATE_DIR/.credentials.json" ] && [ -f "$COMMON_DIR/.credentials.json" ]; then
	cp -a "$COMMON_DIR/.credentials.json" "$STATE_DIR/.credentials.json"
	for name in history.jsonl projects sessions todos; do
		if [ -e "$COMMON_DIR/$name" ] && [ ! -e "$STATE_DIR/$name" ]; then
			cp -a "$COMMON_DIR/$name" "$STATE_DIR/$name"
		fi
	done
	echo "[claude-config] 私的状態を $COMMON_DIR から $STATE_DIR へ移設しました。"
	echo "[claude-config] 移設元（$COMMON_DIR/.credentials.json ほか）は残してあります。"
	echo "[claude-config] 認証が保持されていることを確認したら手動で削除してください。"
fi

echo "[claude-config] config dir=$STATE_DIR / 共通資産=$COMMON_DIR（settings.json・skills・agents を symlink）"
