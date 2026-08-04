#!/bin/bash
# new-service.sh — 新規サービス雛形の生成（プロファイル合成方式。設計の正: docs/decisions/006-adr-profile-based-bootstrap.md）。
# profiles/_base/（共通骨格）を展開した上に、--profile で指定されたプロファイルの
# profile.manifest（add/replace）を重ねて配布する。
# 共通所有の実体（CLAUDE.md・docs/rules/・common/scripts/・common/make/）は**配布しない**。
# 生成先は共通リポの projects/ 配下に置かれ、マーカー .ai-dev-foundation-root 経由で参照する
# （2026-07-30 順輸入廃止・ADR-010。配る＝複製が生まれるため、複製ゼロを設計として選んだ）。
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

# 生成先は**共通基盤の projects/ 配下**（参照方式の必須条件）。ここに置かれることで、生成された
# プロジェクトの Makefile・SessionStart フックがマーカー .ai-dev-foundation-root を上方探索して
# 共通側を解決できる。基盤の兄弟に置くと解決に失敗し、make が即エラーになる（fail-closed）。
# 生成先の差し替えはテスト用（隔離された基盤の複製から生成するため）。
PROJECTS_ROOT="${NEW_SERVICE_PROJECTS_ROOT:-$ROOT/projects}"
TARGET="${PROJECTS_ROOT}/${SERVICE_NAME}"
if [ -d "$TARGET" ]; then
	die_usage "${TARGET} は既に存在します"
fi
echo "=== ${SERVICE_NAME} の雛形を作成します（プロファイル: ${PROFILE}） ==="

BASE="$PROFILES_DIR/_base"

# ---- 手順1: _base（共通骨格）＋ root 正本の展開（ADR-006 §5.1） ----

# ディレクトリ作成
mkdir -p "${TARGET}"/{.devcontainer,.claude,.github/workflows,docs/requirements,docs/service-rules,docs/decisions,scripts}

# devcontainer設定をコピー
cp "$BASE/.devcontainer/Dockerfile" "${TARGET}/.devcontainer/"
cp "$BASE/.devcontainer/postCreate.sh" "${TARGET}/.devcontainer/"
# 外向き既定拒否のファイアウォール（ADR-013 第1層）。Dockerfile が COPY でイメージへ焼く。
cp "$BASE/.devcontainer/init-firewall.sh" "${TARGET}/.devcontainer/"
chmod +x "${TARGET}/.devcontainer/init-firewall.sh"
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

# 共通ルール（CLAUDE.md・docs/rules/）は**配布しない**。実体は共通リポにのみ置き、参照する
# （2026-07-30 順輸入廃止・ADR-010）:
#   - CLAUDE.md  … Claude Code が起動位置から上位ディレクトリを遡って連結する。生成先が共通リポの
#                  projects/ 配下にあるため、直下に無くても共通リポの CLAUDE.md が読み込まれる
#   - docs/rules … session-start-rules.sh がマーカー .ai-dev-foundation-root を上方探索し、
#                  共通側から索引を生成する（1件も解決できなければ警告を注入＝fail-loud）

# サービス固有ルールの雛形を配布（CLAUDE.md が docs/service-rules/consistency.md を参照するため、
# 雛形が無いと全サービスでリンク切れになる。中身はサービスが自スタックで肉付けする＝逆輸入対象外）
cp "$BASE/docs/service-rules/"*.md "${TARGET}/docs/service-rules/"
# ADR（意思決定記録）の運用の型を配布（テンプレート＋運用ガイド。基盤固有のADR本体は配らない）
cp "$BASE/docs/decisions/"*.md "${TARGET}/docs/decisions/"

# 要件トレーサビリティの雛形（要件テンプレ等）を配布（実要件は各サービスが後付け。批准レス運用: ADR-008）
cp "$BASE/docs/requirements/"*.md "${TARGET}/docs/requirements/"

# 品質ゲート一式（Makefile契約・監査雛形・カバレッジ機構・CIワークフロー）を配布。
# 共通スクリプト（pre-push・commit-msg・check-*.sh）は**配らない**。実体は共通リポの
# common/scripts/ にあり、サービスは参照する（2026-07-30 順輸入廃止・ADR-010）:
#   - git フック  … Makefile の install-hooks が common/scripts/ へ ln -sf する
#   - ゲート実装  … common/make/gates.mk が common/scripts/ を直接実行する
#   - CI          … .github/actions/ の composite action を uses: で参照する
cp "$BASE/Makefile" "${TARGET}/Makefile"
cp "$BASE/scripts/audit-consistency.sh" "${TARGET}/scripts/"
cp "$BASE/.coverage-floor" "${TARGET}/.coverage-floor"  # フロア初期値(サービスがラチェット)
cp "$BASE/.req-coverage-baseline" "${TARGET}/.req-coverage-baseline"  # 未カバー要件の移行猶予(空)
cp "$BASE/.tier-tripwire-allow" "${TARGET}/.tier-tripwire-allow"      # トリップワイヤ例外allowlist(空)
chmod +x "${TARGET}/scripts/audit-consistency.sh"
# CIワークフロー（スタック非依存の多段ゲート。詳細: docs/rules/quality-gates.md §4）
cp "$BASE/.github/workflows/ci.yml" "${TARGET}/.github/workflows/ci.yml"

# PROJECT.mdをテンプレートからコピー
cp "$BASE/PROJECT.md.template" "${TARGET}/PROJECT.md"
sed -i "s/\[サービス名\]/${SERVICE_NAME}/g" "${TARGET}/PROJECT.md"

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

echo "✅ ${TARGET} を作成しました（プロファイル: ${PROFILE}）"
echo ""
echo "作成されたファイル:"
find "${TARGET}" -not -path '*/.claude/*' | sort
echo ""
echo "▼ 生成後に対応する項目（要件トレーサビリティ）:"
echo "  - PROJECT.md「Tierトリップワイヤ設定」を埋める。機微面が無ければ docs/requirements/.tier-tripwire-none をコミットして宣言する"
echo "  - 既存仕様の要件化は extract-requirements スキルで docs/requirements/ に起こす（批准レス運用: ADR-008）"
echo ""

# エディタは自動で開かない（bats テスト等からの実行でウィンドウが開いて邪魔になるため。2026-07-22）
echo "開く場合: code \"${TARGET}\""
