#!/usr/bin/env bash
# guard-shim.sh — 番人フック。共通基盤のガードへ委譲するだけの薄いシム。
#
# なぜ必要か（2026-07-26 フェーズ0）:
#   PreToolUse フックのコマンドを "$CLAUDE_PROJECT_DIR/.claude/scripts/guard-dangerous.sh" と
#   書くと、CLAUDE_PROJECT_DIR が**起動ディレクトリ**を指すため（実測）、プロジェクトの
#   サブディレクトリから claude を起動した瞬間にスクリプトが見つからなくなる。そしてフックは
#   スクリプト不在を**無警告で素通し**する（fail-open。実測で確認）。つまりガードも deny も
#   丸ごと無効な状態でセッションが始まり、それに誰も気づけない。
#   このシムはマーカーを上方向に探索し、見つからなければ exit 2 で**ブロックする**。
#   「効いていないのに緑」を「動かないなら止まる」に変えるのが唯一の目的。
set -u

MARKER=".ai-dev-foundation-root"
d="$PWD"
while [ "$d" != "/" ]; do
	if [ -f "$d/$MARKER" ]; then exec bash "$d/.claude/scripts/guard-dangerous.sh" "$@"; fi
	d="$(dirname "$d")"
done
echo "guard-shim: 共通基盤（$MARKER）が見つからず、ガードを実行できないため Bash をブロックします。このリポジトリが共通基盤リポジトリの配下にあるか、devcontainer のマウント設定を確認してください" >&2
exit 2
