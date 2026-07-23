#!/bin/bash
# new-service.sh — 新規サービス雛形の生成（プロファイル合成方式。設計の正: docs/decisions/006-adr-profile-based-bootstrap.md）。
# profiles/_base/（共通骨格）を展開した上に、--profile で指定されたプロファイルの
# profile.manifest（add/replace）を重ねて配布する。root 正本（CLAUDE.md・docs/rules/ 等）は
# _base に複製せず従来どおり root から直接コピーする（正本の二重管理を避ける。ADR-006 §4 の解釈）。
#
# 終了コード: 0=成功 / 1=使い方・引数エラー / 2=manifest 設定エラー（fail-closed）
set -eu
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROFILES_DIR="$ROOT/profiles"

die_usage() { echo "エラー: $1" >&2; exit 1; }
die_manifest() { echo "エラー(manifest): $1" >&2; exit 2; }
trim() { local s="$1"; s="${s#"${s%%[![:space:]]*}"}"; s="${s%"${s##*[![:space:]]}"}"; printf '%s' "$s"; }

# 利用可能プロファイル一覧（profiles/ 直下のうち _base を除き、manifest を持つもの）
available_profiles() {
	local d name
	for d in "$PROFILES_DIR"/*/; do
		name="${d%/}"; name="${name##*/}"
		[ "$name" = "_base" ] && continue
		[ -f "$PROFILES_DIR/$name/profile.manifest" ] && echo "  - $name"
	done
}
usage() {
	{
		echo "使い方: ./scripts/new-service.sh <サービス名> --profile <プロファイル名>"
		echo "利用可能なプロファイル:"
		available_profiles
	} >&2
	exit 1
}

# ---- 引数解釈（--profile 必須。ADR-006 §6） ----
SERVICE_NAME=""
PROFILE=""
while [ $# -gt 0 ]; do
	case "$1" in
		--profile)
			[ -n "${2:-}" ] || die_usage "--profile に値がありません"
			PROFILE="$2"; shift 2 ;;
		--profile=*)
			PROFILE="${1#--profile=}"; shift ;;
		-*)
			die_usage "不明なオプション: $1" ;;
		*)
			[ -z "$SERVICE_NAME" ] || die_usage "サービス名が複数指定されています: '$SERVICE_NAME' と '$1'"
			SERVICE_NAME="$1"; shift ;;
	esac
done
[ -n "$SERVICE_NAME" ] || usage
# サービス名を検証する（英数字始まり・英数字と ._- のみ）。
# パストラバーサル（../x や / 入り）と sed 置換文字列の破壊（/ & \ 入り）を機械的に防ぐため。
if ! printf '%s' "$SERVICE_NAME" | grep -qE '^[a-zA-Z0-9][a-zA-Z0-9._-]*$'; then
	die_usage "サービス名は英数字で始まり、英数字と . _ - のみ使用できます: '${SERVICE_NAME}'"
fi
# プロファイル検証。_base は合成の内部部品であり明示指定の経路を設けない（ADR-006 §6）。
[ -n "$PROFILE" ] || usage
[ "$PROFILE" = "_base" ] && { echo "エラー: _base は内部部品であり直接指定できません。" >&2; usage; }
if ! printf '%s' "$PROFILE" | grep -qE '^[a-zA-Z0-9][a-zA-Z0-9._-]*$'; then
	die_usage "プロファイル名に使用できない文字が含まれています: '${PROFILE}'"
fi
if [ ! -f "$PROFILES_DIR/$PROFILE/profile.manifest" ]; then
	echo "エラー: プロファイル '${PROFILE}' が存在しません。" >&2
	usage
fi

TARGET="$HOME/projects/${SERVICE_NAME}"
if [ -d "$TARGET" ]; then
	die_usage "${TARGET} は既に存在します"
fi
echo "=== ${SERVICE_NAME} の雛形を作成します（プロファイル: ${PROFILE}） ==="

BASE="$PROFILES_DIR/_base"

# ---- 手順1: _base（共通骨格）＋ root 正本の展開（ADR-006 §5.1） ----

# ディレクトリ作成
mkdir -p "${TARGET}"/{.devcontainer,.claude,.github/workflows,docs/rules,docs/requirements,docs/service-rules,docs/decisions,scripts}

# devcontainer設定をコピー
cp "$BASE/.devcontainer/Dockerfile" "${TARGET}/.devcontainer/"
cp "$BASE/.devcontainer/postCreate.sh" "${TARGET}/.devcontainer/"
sed "s/SERVICE_NAME/${SERVICE_NAME}/g" \
	"$BASE/.devcontainer/devcontainer.json" > "${TARGET}/.devcontainer/devcontainer.json"

# Claude設定をコピー
cp "$BASE/.claude/settings.json" "${TARGET}/.claude/settings.json"
# Claude skills・サブエージェント・SessionStartルール注入スクリプト・危険操作ガードフックを配布
mkdir -p "${TARGET}/.claude/scripts" "${TARGET}/.claude/skills" "${TARGET}/.claude/agents"
cp "$BASE/.claude/scripts/session-start-rules.sh" "${TARGET}/.claude/scripts/"
cp "$BASE/.claude/scripts/guard-dangerous.sh" "${TARGET}/.claude/scripts/"
cp -a "$BASE/.claude/skills/." "${TARGET}/.claude/skills/"
cp -a "$BASE/.claude/agents/." "${TARGET}/.claude/agents/"
chmod +x "${TARGET}/.claude/scripts/session-start-rules.sh" "${TARGET}/.claude/scripts/guard-dangerous.sh"

# 共通ルールをそのままコピー（root 正本。_base には複製しない）
# docs/rules 配下はディレクトリ単位でコピーする（個別指定だと新規ルールの配布漏れが起きるため）
cp "$ROOT/CLAUDE.md" "${TARGET}/CLAUDE.md"
cp "$ROOT/docs/rules/"*.md "${TARGET}/docs/rules/"

# サービス固有ルールの雛形を配布（CLAUDE.md が docs/service-rules/consistency.md を参照するため、
# 雛形が無いと全サービスでリンク切れになる。中身はサービスが自スタックで肉付けする＝逆輸入対象外）
cp "$BASE/docs/service-rules/"*.md "${TARGET}/docs/service-rules/"
# ADR（意思決定記録）の運用の型を配布（テンプレート＋運用ガイド。基盤固有のADR本体は配らない）
cp "$BASE/docs/decisions/"*.md "${TARGET}/docs/decisions/"

# 要件トレーサビリティの雛形（要件テンプレ・INVARIANTS・README）を配布（実要件は各サービスが人間批准で後付け）
cp "$BASE/docs/requirements/"*.md "${TARGET}/docs/requirements/"
# CODEOWNERS（要件パスのレビュー必須。所有者はプレースホルダ＝生成後に人間が実ハンドルへ記入する）
cp "$BASE/.github/CODEOWNERS.template" "${TARGET}/.github/CODEOWNERS"

# 品質ゲート一式（Makefile契約・フック・監査雛形・カバレッジ機構・CIワークフロー）を配布
cp "$BASE/Makefile" "${TARGET}/Makefile"
cp "$BASE/scripts/audit-consistency.sh" "${TARGET}/scripts/"
cp "$ROOT/scripts/pre-push" "${TARGET}/scripts/"
cp "$ROOT/scripts/commit-msg" "${TARGET}/scripts/"           # Conventional Commits 検証(中立)
cp "$ROOT/scripts/check-coverage.sh" "${TARGET}/scripts/"    # カバレッジ・ラチェット判定(中立)
cp "$ROOT/scripts/check-requirements-coverage.sh" "${TARGET}/scripts/"  # 要件↔テスト検証(中立)
cp "$ROOT/scripts/check-tier-tripwire.sh" "${TARGET}/scripts/"          # Tierトリップワイヤ(中立)
cp "$BASE/.coverage-floor" "${TARGET}/.coverage-floor"  # フロア初期値(サービスがラチェット)
cp "$BASE/.req-coverage-baseline" "${TARGET}/.req-coverage-baseline"  # 未カバー要件の移行猶予(空)
cp "$BASE/.tier-tripwire-allow" "${TARGET}/.tier-tripwire-allow"      # トリップワイヤ例外allowlist(空)
chmod +x "${TARGET}/scripts/audit-consistency.sh" "${TARGET}/scripts/pre-push" \
         "${TARGET}/scripts/commit-msg" "${TARGET}/scripts/check-coverage.sh" \
         "${TARGET}/scripts/check-requirements-coverage.sh" "${TARGET}/scripts/check-tier-tripwire.sh"
# CIワークフロー（スタック非依存の多段ゲート。詳細: docs/rules/quality-gates.md §4）
cp "$BASE/.github/workflows/ci.yml" "${TARGET}/.github/workflows/ci.yml"

# 逆輸入（サービス→共通）・順輸入（共通→サービス）プロセス一式を新規サービスへ配布
cp "$ROOT/scripts/backport-to-common.sh" "${TARGET}/scripts/"
cp "$ROOT/scripts/sync-from-common.sh" "${TARGET}/scripts/"
cp "$ROOT/.backport-manifest" "${TARGET}/.backport-manifest"
chmod +x "${TARGET}/scripts/backport-to-common.sh" "${TARGET}/scripts/sync-from-common.sh"

# SERVICE.mdをテンプレートからコピー
cp "$BASE/SERVICE.md.template" "${TARGET}/SERVICE.md"
sed -i "s/\[サービス名\]/${SERVICE_NAME}/g" "${TARGET}/SERVICE.md"

# .gitignore / .env.example / README をテンプレートから配布
# （.claude/ 配下は認証情報・セッションログ等を含むため丸ごとは追跡しないが、
#   settings.json・scripts/・skills/ はチーム共有すべき安全な設定なので gitignore テンプレ側で
#   選択的に追跡対象へ戻している。理由: .claude/ を丸ごとgit管理外にすると guard-dangerous.sh 等の
#   安全設定が新規clone・2人目以降のメンバーに配布されないため）
cp "$BASE/gitignore.template" "${TARGET}/.gitignore"
cp "$BASE/.editorconfig" "${TARGET}/.editorconfig"
cp "$BASE/.env.example" "${TARGET}/.env.example"
sed "s/SERVICE_NAME/${SERVICE_NAME}/g" \
	"$BASE/README.md.template" > "${TARGET}/README.md"

# ---- 手順2-3: profile.manifest の解釈と add/replace の適用（ADR-006 §5） ----
# スキーマ（正: docs/rules/repo-layout.md「プロファイル」節）:
#   profile: <名前>                            … 必須。ディレクトリ名と一致しないと exit 2
#   description: <一行>                        … 必須
#   failclosed_profile: <full-red|display-green> … 必須。初期 fail-closed 状態（ADR-006 §7.2。2種のみ）
#   <op> <path>                                … 1行1ファイル。op ∈ {add, replace}。# コメント可
# バリデーションは fail-closed（未知の行・不正値・トラバーサル・空白パス・実体欠落・add先既存・replace先不存在 → exit 2）
MANIFEST="$PROFILES_DIR/$PROFILE/profile.manifest"
FILES_DIR="$PROFILES_DIR/$PROFILE/files"
overlay_paths=()
seen_profile=""
seen_desc=""
seen_fcp=""
while IFS= read -r raw || [ -n "$raw" ]; do
	line="$(trim "${raw%%#*}")"
	[ -n "$line" ] || continue
	case "$line" in
		profile:*)
			val="$(trim "${line#profile:}")"
			[ "$val" = "$PROFILE" ] || die_manifest "profile: の値 '$val' がディレクトリ名 '$PROFILE' と一致しません"
			seen_profile=1; continue ;;
		description:*)
			[ -n "$(trim "${line#description:}")" ] || die_manifest "description: が空です"
			seen_desc=1; continue ;;
		failclosed_profile:*)
			val="$(trim "${line#failclosed_profile:}")"
			case "$val" in
				full-red|display-green) ;;
				*) die_manifest "failclosed_profile の値が不正です: '$val'（許可: full-red | display-green の2種のみ。ADR-006 §7.2）" ;;
			esac
			seen_fcp=1; continue ;;
		add\ *|add$'\t'*|replace\ *|replace$'\t'*) ;;
		*)
			die_manifest "解釈できない行です: '$line'（許可: profile: / description: / add <path> / replace <path>）" ;;
	esac
	op="${line%%[[:space:]]*}"
	path="$(trim "${line#"$op"}")"
	[ -n "$path" ] || die_manifest "$op のパスがありません"
	case "$path" in
		*[[:space:]]*) die_manifest "パスに空白が含まれています: '$path'（決定論のため禁止）" ;;
		/*|*..*)       die_manifest "絶対パス・.. を含むパスは指定できません: '$path'" ;;
	esac
	src="$FILES_DIR/$path"
	dst="$TARGET/$path"
	[ -f "$src" ] || die_manifest "files/ に実体がありません: profiles/$PROFILE/files/$path"
	if [ "$op" = "add" ]; then
		[ ! -e "$dst" ] || die_manifest "add 先が既に存在します（_base と衝突。replace を使うか manifest を見直す）: $path"
	else
		[ -f "$dst" ] || die_manifest "replace 先が存在しません（_base に無いファイル。add を使うか manifest を見直す）: $path"
	fi
	mkdir -p "$(dirname "$dst")"
	cp "$src" "$dst"
	overlay_paths+=("$path")
	echo "  [profile:$PROFILE] $op $path"
done < "$MANIFEST"
[ -n "$seen_profile" ] || die_manifest "profile: ヘッダがありません"
[ -n "$seen_desc" ] || die_manifest "description: ヘッダがありません"
[ -n "$seen_fcp" ] || die_manifest "failclosed_profile: ヘッダがありません（full-red | display-green。分類し忘れ防止の必須キー。ADR-006 §7.2）"

# ---- 手順4: プレースホルダ置換（従来どおり。プロファイルが置いたファイルにも効かせる） ----
for p in ${overlay_paths[@]+"${overlay_paths[@]}"}; do
	sed -i "s/SERVICE_NAME/${SERVICE_NAME}/g; s/\[サービス名\]/${SERVICE_NAME}/g" "$TARGET/$p"
done

echo "✅ ~/projects/${SERVICE_NAME} を作成しました（プロファイル: ${PROFILE}）"
echo ""
echo "作成されたファイル:"
find "${TARGET}" -not -path '*/.claude/*' | sort
echo ""
echo "▼ 生成後に人間が対応する項目（要件トレーサビリティ）:"
echo "  - .github/CODEOWNERS の既定所有者（@shohei-osawa）を確認し、共同開発者・チームがいる場合は行を追加する"
echo "  - 要件パスのブランチ保護を設定する（docs/rules/git.md「要件パスのブランチ保護」チェックリスト）"
echo "  - SERVICE.md「Tierトリップワイヤ設定」を埋める。機微面が無ければ docs/requirements/.tier-tripwire-none を人間 commit で宣言する"
echo "  - 既存仕様の要件化は extract-requirements スキルで下書き→人間批准（docs/requirements/ は人間のみ）"
echo ""

# エディタは自動で開かない（bats テスト等からの実行でウィンドウが開いて邪魔になるため。2026-07-22）
echo "開く場合: code \"${TARGET}\""
