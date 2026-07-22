#!/bin/bash
# SessionStart hook: SERVICE.md と docs/rules/ の内容を Claude のコンテキストに注入する

WORKSPACE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
content=""

# 要件 front-matter の status を読む（check-requirements-coverage.sh の fm_scalar と同解釈）
fm_status() {
	awk '
		NR==1 && $0=="---" { inb=1; next }
		inb && $0=="---"   { exit }
		inb && $0 ~ /^status:[[:space:]]*/ { sub(/^status:[[:space:]]*/,"",$0); gsub(/^"|"$/,"",$0); print $0; exit }
	' "$1"
}

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

# 要件トレーサビリティ状態（G5: 要件着手前提の surface。警告のみ・非ブロックで session は止めない）
REQ_DIR="$WORKSPACE/docs/requirements"
if [ ! -d "$REQ_DIR" ]; then
	req_status="⚠ 要件ディレクトリ docs/requirements/ がありません（要件未定義）。着手前に要件を定義・批准してください（docs/rules/requirements.md）。"
else
	ratified=0; draft=0; other=0; total=0
	for rf in "$REQ_DIR"/R-*.md; do
		[ -f "$rf" ] || continue
		total=$((total + 1))
		case "$(fm_status "$rf")" in
			ratified) ratified=$((ratified + 1)) ;;
			draft)    draft=$((draft + 1)) ;;
			*)        other=$((other + 1)) ;;
		esac
	done
	if [ "$total" -eq 0 ]; then
		req_status="⚠ docs/requirements/ に要件がありません（要件未定義）。グリーンフィールドなら着手時に要件を起こしてください。"
	else
		req_status="要件件数: ratified=${ratified} / draft=${draft}"
		[ "$other" -gt 0 ] && req_status="${req_status} / その他=${other}"
		if [ "$draft" -gt 0 ]; then
			req_status="${req_status}"$'\n'"⚠ 未批准(draft)の要件が ${draft} 件あります。批准は人間のみ（docs/rules/requirements.md）。未批准要件に紐づくテストは req-coverage で dangling＝赤になります。"
		fi
	fi
fi
content+="=== 要件トレーサビリティ状態 ==="$'\n'"${req_status}"$'\n\n'

# JSON 生成は jq に委ねる（手組み sed エスケープはタブ・CR・制御文字を取りこぼし不正な JSON になるため）。
# jq は guard-dangerous.sh と共通の devcontainer 依存（Dockerfile で導入済み）。
jq -n --arg ctx "$content" \
	'{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$ctx}}'
