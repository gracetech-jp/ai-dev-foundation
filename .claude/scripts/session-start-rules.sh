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

# JSON 生成は jq に委ねる（手組み sed エスケープはタブ・CR・制御文字を取りこぼし不正な JSON になるため）。
# jq は guard-dangerous.sh と共通の devcontainer 依存（Dockerfile で導入済み）。
jq -n --arg ctx "$content" \
	'{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$ctx}}'
