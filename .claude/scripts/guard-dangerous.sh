#!/bin/bash
# PreToolUse hook: permissions.deny の文字列一致をすり抜ける表記ゆれ（rm -fr、git push --force 系の
# フラグ順違い・チェイン実行等）と、bash経由での.env系秘密ファイル読み取りを決定論的に遮断する。
# permissions.deny（settings.json）はコマンド先頭の文字列一致のみのため、`&&`連結・変数プレフィックス・
# フラグの順序違いをすり抜ける。ここでは正規表現でコマンド全体を検査し、その穴を塞ぐ。

set -u

INPUT="$(cat)"

TOOL_NAME="$(echo "$INPUT" | jq -r '.tool_name // empty')"
[ "$TOOL_NAME" = "Bash" ] || exit 0

COMMAND="$(echo "$INPUT" | jq -r '.tool_input.command // empty')"
[ -n "$COMMAND" ] || exit 0

deny() {
	jq -n --arg reason "$1" \
		'{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$reason}}'
	exit 0
}

# 1) rm -rf 系の表記ゆれ（-fr / -Rf / --force --recursive / -r -f 分離 等。大文字小文字を区別しない）
if echo "$COMMAND" | grep -qiE '\b(sudo[[:space:]]+)?\\?rm\b[[:space:]]+(-[a-z]*(r[a-z]*f|f[a-z]*r)[a-z]*\b|--recursive\b.*--force\b|--force\b.*--recursive\b|-r\b.*-f\b|-f\b.*-r\b)'; then
	deny "破壊的なrm(-rf系)コマンドの表記ゆれを検知したためブロックしました"
fi

# 2) git push --force 系（-f 単独・--force・--force-with-lease、チェイン実行含む）
if echo "$COMMAND" | grep -qiE 'git[[:space:]]+push\b[^|;&]*(--force(-with-lease)?\b|[[:space:]]-f([[:space:]]|$))'; then
	deny "git push --force系コマンドを検知したためブロックしました"
fi

# 3) git reset --hard（空白ゆれ・チェイン実行含む）
if echo "$COMMAND" | grep -qiE 'git[[:space:]]+reset\b.*--hard\b'; then
	deny "git reset --hard を検知したためブロックしました"
fi

# 4) git clean -f 系（-fd/-dfx等の結合フラグ含む）
if echo "$COMMAND" | grep -qiE 'git[[:space:]]+clean\b[^|;&]*-[a-z]*f'; then
	deny "git clean -f系コマンドを検知したためブロックしました"
fi

# 5) git branch -D（強制削除）
if echo "$COMMAND" | grep -qE 'git[[:space:]]+branch\b.*-D\b'; then
	deny "git branch -D を検知したためブロックしました"
fi

# 6) git checkout による変更破棄（git checkout -- . / git checkout .）
if echo "$COMMAND" | grep -qiE 'git[[:space:]]+checkout\b[[:space:]]+(--[[:space:]]+\.|\.[[:space:]]*$)'; then
	deny "git checkout による変更破棄を検知したためブロックしました"
fi

# 7) .env系秘密ファイルのbash経由読み取り（.env.example/.sample/.template/.distは対象外）
# `(\.[a-zA-Z0-9_]+)*` は .env.production.local のような多段サフィックスにも一致させるため * とする（? だと1段しか許容できない）
SANITIZED="$(echo "$COMMAND" | sed -E 's/\.env\.(example|sample|template|dist)\b//gi')"
if echo "$SANITIZED" | grep -qiE '\b(cat|less|more|head|tail|tac|strings|xxd|hexdump|od|vim|vi|nano|emacs|cp|scp|base64|awk|sed|grep|diff)\b[^|;&]*\.env(\.[a-zA-Z0-9_]+)*([[:space:]]|$|[^.a-zA-Z0-9_])'; then
	deny ".envなど秘密情報ファイルのbash経由読み取りを検知したためブロックしました"
fi

# 8) 鍵・認証情報ファイルのbash経由読み取り（秘密鍵/SSH/AWS/GCP認証/トークン。id_*.pub 公開鍵は対象外）
SECRETSCAN="$(echo "$COMMAND" | sed -E 's/id_(rsa|ed25519|ecdsa|dsa)\.pub\b//gi')"
if echo "$SECRETSCAN" | grep -qiE '\b(cat|less|more|head|tail|tac|strings|xxd|hexdump|od|vim|vi|nano|emacs|cp|scp|base64|awk|sed|grep|diff)\b[^|;&]*([^[:space:]]*\.(pem|key|p12|pfx)\b|[^[:space:]]*id_(rsa|ed25519|ecdsa|dsa)\b|[^[:space:]]*\.npmrc\b|[^[:space:]]*/\.ssh/|[^[:space:]]*/\.aws/credentials\b|[^[:space:]]*/\.config/gcloud/)'; then
	deny "鍵・認証情報ファイルのbash経由読み取りを検知したためブロックしました"
fi

exit 0
