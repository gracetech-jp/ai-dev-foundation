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

# docs/rules/ はインデックスのみ注入する（全文注入は約54KB/セッションの固定トークン税となるため
# 2026-07-22 に廃止。docs/rules/token-efficiency.md「必要な範囲のみ読む」に従い、詳細は必要時に Read する）。
# 各行の要約はファイルの H1 から自動抽出する（ハードコードすると改名・追加時に要約がドリフトするため）。
content+="=== docs/rules/ インデックス（各ルールの詳細は、必要になった時点で該当ファイルを Read すること） ==="$'\n'
for f in "$WORKSPACE/docs/rules/"*.md; do
	[ -f "$f" ] || continue
	h1="$(grep -m1 '^# ' "$f" | sed 's/^#[[:space:]]*//')"
	content+="- docs/rules/$(basename "$f") — ${h1:-（見出しなし）}"$'\n'
done
content+=$'\n'

# 要件トレーサビリティ状態（G5: 要件着手前提の surface。警告のみ・非ブロックで session は止めない）
REQ_DIR="$WORKSPACE/docs/requirements"
if [ ! -d "$REQ_DIR" ]; then
	req_status="⚠ 要件ディレクトリ docs/requirements/ がありません（要件未定義）。着手前に要件を定義してください（docs/rules/requirements.md）。"
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
			req_status="${req_status}"$'\n'"⚠ draft の要件が ${draft} 件あります。内容を確定したら status: ratified に更新すること（draft のままの要件に紐づくテストは req-coverage で dangling＝赤になります。docs/rules/requirements.md）。"
		fi
	fi
fi
content+="=== 要件トレーサビリティ状態 ==="$'\n'"${req_status}"$'\n'
# 要件の扱いは自己完結の1文で常設する（Read 前に原則が伝わるように。2026-07-24 批准レス化・ADR-008）
content+="📌 docs/requirements/ は永続要件資産（一意ID・再利用禁止）。LLM も直接編集できるが、実装の都合に合わせて既存要件の意味を書き換えることは禁止 — 要件の意味変更・削除はユーザーの了解を得てから行い、理由をコミットに残す（詳細: docs/rules/requirements.md）。"$'\n\n'

# JSON 生成は jq に委ねる（手組み sed エスケープはタブ・CR・制御文字を取りこぼし不正な JSON になるため）。
# jq は guard-dangerous.sh と共通の devcontainer 依存（Dockerfile で導入済み）。
jq -n --arg ctx "$content" \
	'{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$ctx}}'
