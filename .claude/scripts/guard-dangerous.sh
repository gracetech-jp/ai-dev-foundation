#!/bin/bash
# PreToolUse hook: permissions.deny の文字列一致をすり抜ける表記ゆれ（rm -fr・混在フラグ・
# パス先行の引数順・クォート分割、git push --force 系のフラグ順違い・チェイン実行等）と、
# bash経由での.env系秘密ファイル読み取りを決定論的に遮断する。
# permissions.deny（settings.json）はコマンド先頭の文字列一致のみのため、`&&`連結・変数プレフィックス・
# フラグの順序違いをすり抜ける。ここではコマンド全体を検査し、その穴を塞ぐ。
# 方針:
#  - 破壊的コマンド（rm/git系）はセグメント（| ; & && ||・改行の区切り）単位で判定する。
#    フラグの位置・順序・結合/分離/ロングショート混在に依存せず、誤検知もセグメント内に閉じる。
#  - 秘密ファイル読み取りはコマンド全体の共起で判定する（`echo .env | xargs cat` のような
#    パイプ跨ぎを塞ぐため）。ガードは過剰側に倒す（fail-safe）。
#  - 正規表現は GNU 拡張の \b を使わず POSIX 文字クラスで書く（BSD/macOS grep で黙って素通しになるのを防ぐ）。

set -u

# jq はフックJSON解析に必須。不在ならコマンドを検査できない＝環境の破損なので fail-closed。
# exit 2 は PreToolUse のブロッキングエラー（stderr が Claude に渡り、Bash実行自体が止まる）。
if ! command -v jq >/dev/null 2>&1; then
	echo "guard-dangerous: jq が見つからずコマンドを検査できないため、Bash実行をブロックします（devcontainer の Dockerfile が jq を導入しているか確認してください）" >&2
	exit 2
fi

INPUT="$(cat)"

TOOL_NAME="$(printf '%s' "$INPUT" | jq -r '.tool_name // empty')"
[ "$TOOL_NAME" = "Bash" ] || exit 0

COMMAND="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty')"
[ -n "$COMMAND" ] || exit 0

deny() {
	jq -n --arg reason "$1" \
		'{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$reason}}'
	exit 0
}

# 検査用に引用符・バックスラッシュを除去した複製。rm -r'f' や rm -r\f のような
# クォート/エスケープ分割によるすり抜けを防ぐ（引用文字列の中身にも一致し得るが過剰側に倒す）。
STRIPPED="$(printf '%s' "$COMMAND" | tr -d '\\"' | tr -d "'")"

# ---- 破壊的コマンド検査（セグメント単位） ----
while IFS= read -r seg; do
	# 1) rm の再帰＋強制。再帰(-r/-R/--recursive)と強制(-f/--force)が同一セグメントの
	#    rm 呼び出しに揃ったら deny。結合(-fr/-Rf)・分離(-r -f)・混在(-r --force)・
	#    パス先行(rm dir -rf)のいずれも位置・順序によらず検知する。
	if printf '%s' "$seg" | grep -qiE '(^|[^[:alnum:]_.-])rm([^[:alnum:]_.-]|$)'; then
		if printf '%s' "$seg" | grep -qiE '(^|[[:space:]])(--recursive([^[:alnum:]-]|$)|-[a-z]*r)' &&
		   printf '%s' "$seg" | grep -qiE '(^|[[:space:]])(--force([^[:alnum:]-]|$)|-[a-z]*f)'; then
			deny "破壊的なrm(-rf系)コマンドを検知したためブロックしました"
		fi
	fi

	# 2) git push --force 系（-f 単独・--force・--force-with-lease[=ref]）
	if printf '%s' "$seg" | grep -qiE 'git[[:space:]]+push[[:space:]](.*[[:space:]])?(--force(-with-lease)?(=[^[:space:]]*)?|-f)([[:space:]]|$)'; then
		deny "git push --force系コマンドを検知したためブロックしました"
	fi

	# 3) git reset --hard
	if printf '%s' "$seg" | grep -qiE 'git[[:space:]]+reset[[:space:]].*--hard([^[:alnum:]-]|$)'; then
		deny "git reset --hard を検知したためブロックしました"
	fi

	# 4) git clean -f 系（-fd/-dfx等の結合フラグ・--force 含む）
	if printf '%s' "$seg" | grep -qiE 'git[[:space:]]+clean([^[:alnum:]_]|$)' &&
	   printf '%s' "$seg" | grep -qiE '(^|[[:space:]])(-[a-z]*f|--force([^[:alnum:]-]|$))'; then
		deny "git clean -f系コマンドを検知したためブロックしました"
	fi

	# 5) git branch の強制削除（-D、結合フラグ、--delete と --force の併用）
	if printf '%s' "$seg" | grep -qiE 'git[[:space:]]+branch([^[:alnum:]_]|$)'; then
		if printf '%s' "$seg" | grep -qE '(^|[[:space:]])-[A-Za-z]*D' ||
		   { printf '%s' "$seg" | grep -qiE '(^|[[:space:]])--delete([^[:alnum:]-]|$)' &&
		     printf '%s' "$seg" | grep -qiE '(^|[[:space:]])--force([^[:alnum:]-]|$)'; }; then
			deny "git branch の強制削除(-D)を検知したためブロックしました"
		fi
	fi

	# 6) git checkout による変更破棄（git checkout -- . / git checkout .）
	if printf '%s' "$seg" | grep -qiE 'git[[:space:]]+checkout[[:space:]]+(--[[:space:]]+\.([[:space:]]|$)|\.[[:space:]]*$)'; then
		deny "git checkout による変更破棄を検知したためブロックしました"
	fi
done < <(printf '%s\n' "$STRIPPED" | awk '{gsub(/\|\||&&|[|;&]/, "\n"); print}')

# ---- 秘密ファイル読み取り検査（コマンド全体の共起） ----
# 読み取り系コマンドと秘密ファイルパスが同一コマンド内に共起したら deny。
# セグメントを跨ぐデータフロー（echo .env | xargs cat 等）は正規表現で追えないため、全体共起で塞ぐ。
READERS='(^|[^[:alnum:]_.-])(cat|less|more|head|tail|tac|strings|xxd|hexdump|od|vim|vi|nano|emacs|cp|scp|dd|base64|awk|sed|grep|rg|nl|bat|jq|diff|source|xargs)([^[:alnum:]_]|$)'

# 7) .env系（.env.example/.sample/.template/.dist は対象外として先に除去。
#    `(\.[a-zA-Z0-9_]+)*` は .env.production.local のような多段サフィックスにも一致させるため * とする）
SANITIZED="$(printf '%s' "$STRIPPED" | awk '{gsub(/\.env\.(example|sample|template|dist)/, ""); print}')"
if printf '%s' "$SANITIZED" | grep -qiE "$READERS" &&
   printf '%s' "$SANITIZED" | grep -qiE '\.env(\.[a-zA-Z0-9_]+)*([^.a-zA-Z0-9_]|$)'; then
	deny ".envなど秘密情報ファイルのbash経由読み取りを検知したためブロックしました"
fi

# 8) 鍵・認証情報ファイル（秘密鍵/SSH/AWS/GCP認証/トークン。id_*.pub 公開鍵は対象外として先に除去）
SECRETSCAN="$(printf '%s' "$STRIPPED" | awk '{gsub(/id_(rsa|ed25519|ecdsa|dsa)\.pub/, ""); print}')"
if printf '%s' "$SECRETSCAN" | grep -qiE "$READERS" &&
   printf '%s' "$SECRETSCAN" | grep -qiE '(\.(pem|key|p12|pfx)([^[:alnum:]_]|$)|id_(rsa|ed25519|ecdsa|dsa)([^[:alnum:]_]|$)|\.npmrc([^[:alnum:]_]|$)|/\.ssh/|\.ssh/|/\.aws/credentials([^[:alnum:]_]|$)|/\.config/gcloud/)'; then
	deny "鍵・認証情報ファイルのbash経由読み取りを検知したためブロックしました"
fi

exit 0
