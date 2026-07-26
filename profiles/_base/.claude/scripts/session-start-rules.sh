#!/bin/bash
# SessionStart hook: SERVICE.md と docs/rules/ の内容を Claude のコンテキストに注入する

# ---- ルート解決（2026-07-26 フェーズ1: ユーザースコープ配布に対応） ----
# 共通の .claude を /home/node/.claude へマウントして配る方式では、このスクリプトの位置は
# 共通側になる。BASH_SOURCE から2階層上を取ると /home/node を指してしまい、SERVICE.md も
# docs/rules も見つからないまま**無言で空の注入**になる。そのためルートは位置ではなく
# 起動コンテキストから決める。
#
#   WORKSPACE   … このプロジェクト（SERVICE.md・docs/requirements の所在）
#   COMMON_ROOT … 共通基盤（docs/rules の所在）。マーカーを上方向に探索する
#
# CLAUDE_PROJECT_DIR は起動ディレクトリを指す（実測）。サブディレクトリ起動でも正しい
# プロジェクトルートに落とすため、git のトップレベルを優先する。
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
WORKSPACE="$(git -C "$PROJECT_DIR" rev-parse --show-toplevel 2>/dev/null || printf '%s' "$PROJECT_DIR")"

COMMON_ROOT=""
_d="$WORKSPACE"
while [ "$_d" != "/" ]; do
	if [ -f "$_d/.ai-dev-foundation-root" ]; then COMMON_ROOT="$_d"; break; fi
	_d="$(dirname "$_d")"
done

# ルール本体の所在。参照方式なら共通側、移行前の複製方式ならプロジェクト側（後方互換）。
if [ -n "$COMMON_ROOT" ] && [ -d "$COMMON_ROOT/docs/rules" ]; then
	RULES_DIR="$COMMON_ROOT/docs/rules"
else
	RULES_DIR="$WORKSPACE/docs/rules"
fi

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
rules_found=0
for f in "$RULES_DIR/"*.md; do
	[ -f "$f" ] || continue
	rules_found=1
	h1="$(grep -m1 '^# ' "$f" | sed 's/^#[[:space:]]*//')"
	content+="- $f — ${h1:-（見出しなし）}"$'\n'
done
# 1件も見つからないのは「ルールが無い」ではなく「解決に失敗している」状態。
# 黙って空の索引を出すと、共通ルールが読まれていないことに誰も気づけない（fail-loud）。
if [ "$rules_found" -eq 0 ]; then
	content+="⚠⚠ 共通ルールが1件も見つかりません（探索先: $RULES_DIR）。"$'\n'
	content+="   このリポジトリが共通基盤リポジトリの配下にあるか、devcontainer のマウント設定を確認してください。"$'\n'
	content+="   共通ルールが読み込まれていない状態で作業を進めないこと。"$'\n'
fi
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
