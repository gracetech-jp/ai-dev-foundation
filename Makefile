# AI Dev Foundation — 品質ゲートの入口（docs/rules/quality-gates.md の Makefile ターゲット契約）
# フック・CI・人間が同じ入口を共有するための規約ターゲット。
# この基盤リポジトリはアプリコードを持たないが、配布するシェル資産（ガードレール等）を
# bats で自己検証する。test は「スクリプト構文チェック + bats シェルテスト」を担い、
# audit-all（ドキュメント/テンプレートの整合性監査）と二本立てで品質を担保する。

.PHONY: all test lint coverage req-coverage tier-tripwire audit-all audit-deps install-hooks

all: audit-all test req-coverage tier-tripwire

# 全テスト実行。まず配布シェル資産の構文を検査し、続いて bats でガードレール等の挙動を検証する。
# bats 不在は fail-closed（黙ってスキップするとシェル資産のゲートが形骸化するため。lint と同方針）。
# devcontainer には Dockerfile で、CI には ubuntu ランナーの apt で導入する。
# サービスリポジトリ側は各スタックのテストランナーで上書きする（bats は基盤の dogfood 専用）。
test:
	@echo "[test] 配布シェル資産の構文を検査します。"
	@for f in scripts/*.sh scripts/pre-push scripts/commit-msg .claude/scripts/*.sh templates/.claude/scripts/*.sh templates/scripts/*.sh templates/.devcontainer/postCreate.sh; do bash -n "$$f" || exit 1; done
	@command -v bats >/dev/null 2>&1 || { echo "[test] ❌ bats が見つかりません（fail-closed。導入: apt-get install bats）"; exit 1; }
	@echo "[test] bats を実行中..."
	@bats tests/
	@echo "[test] ✅ 構文チェック + bats 通過"

# 静的解析（ゼロ警告ゲート）。shellcheck 不在は fail-closed（黙ってスキップするとゲートが形骸化するため）。
# devcontainer には Dockerfile で導入済み。CI の ubuntu ランナーにもプリインストールされている。
lint:
	@command -v shellcheck >/dev/null 2>&1 || { echo "[lint] ❌ shellcheck が見つかりません（fail-closed。導入: apt-get install shellcheck）"; exit 1; }
	@echo "[lint] shellcheck を実行中..."
	@shellcheck scripts/*.sh scripts/pre-push scripts/commit-msg .claude/scripts/*.sh templates/.claude/scripts/*.sh templates/scripts/*.sh templates/.devcontainer/postCreate.sh || exit 1
	@echo "[lint] ✅ 警告なし"

# カバレッジのフロア検証（ラチェット）。基盤リポはアプリコードが無いためスキップ。
# サービス側はカバレッジを計測し scripts/check-coverage.sh に測定値を渡して失敗判定する。
coverage:
	@echo "[coverage] 基盤リポにカバレッジ対象のアプリコードはありません。スキップします。"

# 要件↔テストのカバレッジ・妥当性・改変検知（詳細: docs/rules/requirements.md / testing.md）。
# 基盤は bats テストにコメントマーカー（# @req: R-xxx / # @adversarial: R-xxx）で要件を紐づける。
# マーカー走査設定はスタック依存のため env で渡す（サービス側は SERVICE.md 由来の値を Makefile で設定）。
req-coverage:
	@REQ_TEST_PATHS="tests" \
	 REQ_MARKER_RE='@req:?[[:space:]]*R-[0-9]+' \
	 ADV_MARKER_RE='@adversarial:?[[:space:]]*R-[0-9]+' \
	 REQ_COMMENT_PREFIX='#' \
	 bash scripts/check-requirements-coverage.sh

# Tierトリップワイヤ（Tier デスカレーションをコード実態から裏取り。詳細: docs/rules/tiers.md）。
# 基盤 ai-dev-foundation は機微プロダクトコードを持たないため「機微面なし」を宣言する運用:
# 空設定＋ docs/requirements/.tier-tripwire-none（人間 commit で ratify）で正当スキップになる。
tier-tripwire:
	@TIER_TRIPWIRE_PATHS="" TIER_TRIPWIRE_SYMBOLS="" \
	 bash scripts/check-tier-tripwire.sh

# 整合性監査一式（詳細: docs/rules/consistency.md）
audit-all:
	@bash scripts/audit-consistency.sh

# 依存パッケージの脆弱性監査。基盤リポは外部ランタイム依存が無いためスキップ。
audit-deps:
	@echo "[audit-deps] 基盤リポに外部ランタイム依存はありません。スキップします。"

# git フック（pre-push・commit-msg）をローカルに導入する
install-hooks:
	@ln -sf ../../scripts/pre-push "$$(git rev-parse --git-dir)/hooks/pre-push"
	@ln -sf ../../scripts/commit-msg "$$(git rev-parse --git-dir)/hooks/commit-msg"
	@chmod +x scripts/pre-push scripts/commit-msg
	@echo "[install-hooks] ✅ pre-push・commit-msg フックを導入しました"
