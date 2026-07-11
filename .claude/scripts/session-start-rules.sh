#!/bin/bash
# SessionStart hook: SERVICE.md と docs/rules/ の内容を Claude のコンテキストに注入する

WORKSPACE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
content=""

# SERVICE.md
if [ -f "$WORKSPACE/SERVICE.md" ]; then
	content+="$(cat "$WORKSPACE/SERVICE.md")"$'\n\n'
fi

# docs/rules/ 配下の全 .md ファイル
for f in "$WORKSPACE/docs/rules/"*.md; do
	[ -f "$f" ] || continue
	content+="=== $(basename "$f") ==="$'\n'
	content+="$(cat "$f")"$'\n\n'
done

# bash で JSON エスケープ: \, " を先にエスケープし、改行を \n に変換
escaped=$(printf '%s' "$content" \
	| sed 's/\\/\\\\/g' \
	| sed 's/"/\\"/g' \
	| sed ':a;N;$!ba;s/\n/\\n/g')

printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' "$escaped"
