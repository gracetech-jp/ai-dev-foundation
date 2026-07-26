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
#
# 委譲の失敗も止める（2026-07-26 是正）:
#   当初は `exec bash <ガード>` としていたが、委譲先が存在しないと exec が失敗して exit 127 で
#   終わる。PreToolUse がブロックと解釈するのは exit 2 だけなので、**127 は素通しになる**。
#   マーカーだけ見つかってガード本体が見えない構成（共通側の .claude が未マウント等）で
#   実際に fail-open していた。事前に存在と可読性を確認し、実行できなかった場合（126/127）も
#   exit 2 に倒す。exec をやめたのは、exec 後は失敗を検知できないため。
set -u

MARKER=".ai-dev-foundation-root"
d="$PWD"
while [ "$d" != "/" ]; do
	if [ -f "$d/$MARKER" ]; then
		GUARD="$d/.claude/scripts/guard-dangerous.sh"
		if [ ! -f "$GUARD" ] || [ ! -r "$GUARD" ]; then
			echo "guard-shim: 共通基盤は見つかりましたが、委譲先のガードが読めないため Bash をブロックします: $GUARD（devcontainer が共通側の .claude をこの位置にマウントしているか確認してください）" >&2
			exit 2
		fi
		bash "$GUARD" "$@"
		rc=$?
		if [ "$rc" -eq 126 ] || [ "$rc" -eq 127 ]; then
			echo "guard-shim: ガードを実行できませんでした（exit $rc）。素通しさせないため Bash をブロックします: $GUARD" >&2
			exit 2
		fi
		exit "$rc"
	fi
	d="$(dirname "$d")"
done
echo "guard-shim: 共通基盤（$MARKER）が見つからず、ガードを実行できないため Bash をブロックします。このリポジトリが共通基盤リポジトリの配下にあるか、devcontainer のマウント設定を確認してください" >&2
exit 2
