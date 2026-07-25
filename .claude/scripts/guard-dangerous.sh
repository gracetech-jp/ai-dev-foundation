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

# （2026-07-24 批准レス化・ADR-008: 要件ディレクトリ docs/requirements/ への書き込み遮断（旧G3）は撤去。
#   要件は LLM も直接編集できる。トレーサビリティの担保は req-coverage / tier-tripwire の機械ゲートで行う）

# ---- 共通所有ファイルへの bash 経由書き込み遮断（ADR-009: サービス側は編集・還流禁止、順輸入のみ） ----
# 対象は「新規サービス構築後、仕組みを疑わなければ触ることがない」共通所有ファイルに限る。
# サービス側で編集が前提の箇所（SERVICE.md・Makefile 実装・audit-consistency.sh 肉付け・
# docs/requirements/・ci.yml・.gitignore 追記等）は対象外。settings.json の deny と対で機械強制する。
# 基盤リポ ai-dev-foundation 自身は共通所有ファイルの編集元のため対象外
# （profiles/_base/ の存在で決定論的に判定。プロジェクトルートは CLAUDE_PROJECT_DIR、無ければ cwd）。
# 更新の正規経路は sync-from-common.sh の実行のみ（スクリプト起動コマンドは書込系と共起しないため素通し）。
if [ ! -d "${CLAUDE_PROJECT_DIR:-$PWD}/profiles/_base" ]; then
	COMMON_OWNED='(CLAUDE\.md|docs/rules/|\.claude/settings\.json|\.claude/scripts/(guard-dangerous|session-start-rules)\.sh|\.claude/skills/(extract-requirements|verify-request)/|\.claude/agents/(consistency-auditor|security-reviewer)\.md|scripts/(pre-push|commit-msg|check-coverage\.sh|check-requirements-coverage\.sh|check-tier-tripwire\.sh|sync-from-common\.sh))'
	if printf '%s' "$STRIPPED" | grep -qE "$COMMON_OWNED"; then
		# a) リダイレクト（> / >> / >|）先が共通所有ファイル
		#    >| は noclobber 無効化つき上書き。`[^|...]` が直後の | でパイプと誤認し素通ししていたため明示的に許容する。
		if printf '%s' "$STRIPPED" | grep -qE ">[>|]?[[:space:]]*[^|;&<>]*$COMMON_OWNED"; then
			deny "共通所有ファイルへのリダイレクト書き込みを検知したためブロックしました（サービス側は編集禁止・更新は順輸入のみ。ADR-009）"
		fi
		# b) 変更系コマンド（rm/tee/cp/mv/dd/install/truncate/patch/rsync/sed -i）が共通所有ファイルと共起（過剰側=fail-safe）。
		#    rm は 2026-07-25 に追加（sumai-desk の申し送り。破壊的コマンド検査は rm -rf 等の再帰強制しか見ないため、
		#    `rm CLAUDE.md` のような単純削除が素通ししていた。編集より影響が大きい経路が無防備だった）。
		#    perl -pi / python -c / ln -sf 等のインタプリタ経由は意図的に列挙しない（コマンドを必要以上に
		#    制限しない方針。2026-07-25 ユーザー判断。ここは列挙で塞ぐ設計であり網羅は目指さない）。
		#    破壊的コマンド検査と同じセグメント単位で判定する。コマンド全体で1回だけ判定すると、
		#    正規の骨格同期を1つ含めるだけでチェイン内の別の書き込みまで免除されてしまうため（2026-07-25 是正）。
		#    例外: 基盤の profiles/_base/ を**コピー元の第1引数**に取る骨格同期だけを通す。
		#    これはマニフェスト対象外の `.claude/` 等を更新する唯一の正規手順（docs/rules/backport.md §骨格は手動同期）で、
		#    b) が無条件に塞ぐと正規の更新経路そのものが消える。コピー元位置に限定しているので、
		#    末尾コメントや第2引数に profiles/_base/ を書き足して素通しさせる細工は成立しない。
		skeleton_sync='^[[:space:]]*(cp|rsync|install)([[:space:]]+-[^[:space:]]+)*[[:space:]]+[^[:space:]]*profiles/_base/'
		while IFS= read -r seg; do
			printf '%s' "$seg" | grep -qE "$COMMON_OWNED" || continue
			printf '%s' "$seg" | grep -qE "$skeleton_sync" && continue
			if printf '%s' "$seg" | grep -qE '(^|[^[:alnum:]_.-])(rm|tee|cp|mv|dd|install|truncate|patch|rsync)([^[:alnum:]_]|$)' ||
			   printf '%s' "$seg" | grep -qE '(^|[^[:alnum:]_.-])sed([^[:alnum:]_]|$).*-i'; then
				deny "共通所有ファイルへの bash 経由の書き込み/変更を検知したためブロックしました（サービス側は編集禁止・更新は順輸入のみ。ADR-009）"
			fi
		done < <(printf '%s\n' "$STRIPPED" | awk '{gsub(/\|\||&&|[|;&]/, "\n"); print}')
	fi
fi

exit 0
