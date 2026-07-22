# SERVICE_NAME — 品質ゲートの入口（static-site プロファイル実装。docs/rules/quality-gates.md の Makefile ターゲット契約）
# フック・CI・人間が同じ入口を共有するための規約ターゲット。
# スタック: Astro SSG + pnpm（Node 24）。初期状態は display-green（ADR-006 §7.2）:
#   表示・ビルド系は生成直後から緑。ただし黙って通さず、未実装の理由を警告 echo で明示する。
#   package.json / 各 script が出来た瞬間から実コマンドが走る条件分岐であり、恒久的な素通しではない。

.PHONY: all test lint coverage req-coverage tier-tripwire audit-all audit-deps install-hooks build

all: audit-all test req-coverage tier-tripwire

# 全テスト実行（pnpm）。test script が定義された時点から実コマンドが走る。
test:
	@if [ ! -f package.json ]; then \
		echo "[test] ⚠ package.json がありません（Astroプロジェクト未作成）。skip（display-green）"; \
	elif jq -e '.scripts.test' package.json >/dev/null 2>&1; then \
		pnpm run test; \
	else \
		echo "[test] ⚠ package.json に test script が未定義です（テスト導入時に scripts.test を定義すること）。skip（display-green）"; \
	fi

# 静的解析。ゼロ警告ゲート（サービスの lint script 側で警告ゼロ失敗を設定する。例: eslint --max-warnings=0）。
lint:
	@if [ ! -f package.json ]; then \
		echo "[lint] ⚠ package.json がありません（Astroプロジェクト未作成）。skip（display-green）"; \
	elif jq -e '.scripts.lint' package.json >/dev/null 2>&1; then \
		pnpm run lint; \
	else \
		echo "[lint] ⚠ package.json に lint script が未定義です（導入時に scripts.lint を警告ゼロ設定で定義すること）。skip（display-green）"; \
	fi

# ビルド（契約外の便宜ターゲット）。Astro プロジェクトが出来た時点から pnpm run build が走る。
build:
	@if [ ! -f package.json ]; then \
		echo "[build] ⚠ package.json がありません（Astroプロジェクト未作成）。skip（display-green）"; \
	elif jq -e '.scripts.build' package.json >/dev/null 2>&1; then \
		pnpm run build; \
	else \
		echo "[build] ⚠ package.json に build script が未定義です。skip（display-green）"; \
	fi

# カバレッジのフロア検証（一方向ラチェット。docs/rules/quality-gates.md §5）。
# 静的サイトの初期は 0床（ADR-006 C-2）。ロジック（Pages Functions 等）を持ったら
# 実測値を scripts/check-coverage.sh に渡す形へ置換し、.coverage-floor を引き上げる（床は下げない）。
coverage:
	@bash scripts/check-coverage.sh 0

# 依存パッケージの脆弱性監査（docs/rules/security.md）。lockfile が出来た時点から実監査が走る。
audit-deps:
	@if [ -f package.json ] && [ -f pnpm-lock.yaml ]; then \
		pnpm audit --audit-level=high; \
	else \
		echo "[audit-deps] ⚠ package.json / pnpm-lock.yaml がありません（依存未導入）。skip（display-green）"; \
	fi

# 要件↔テストのカバレッジ・妥当性・改変検知（docs/rules/requirements.md / testing.md）。
# JS系のマーカー走査デフォルト（display-green: 生成直後は要件0件で緑。要件を持った時点から実検証される）。
req-coverage:
	@REQ_TEST_PATHS="tests src" \
	 REQ_MARKER_RE='@req:?[[:space:]]*R-[0-9]+' \
	 ADV_MARKER_RE='@adversarial:?[[:space:]]*R-[0-9]+' \
	 REQ_COMMENT_PREFIX='//' \
	 bash scripts/check-requirements-coverage.sh

# Tierトリップワイヤ（docs/rules/tiers.md / SERVICE.md「Tierトリップワイヤ設定」）。
# static-site は docs/requirements/.tier-tripwire-none を同梱しており、空設定で正当スキップする。
# 機微（問い合わせフォーム等の外部公開・個人情報を扱う部分）を実装したら、要件化のうえ
# TIER_TRIPWIRE_PATHS を設定して締め直すこと（.tier-tripwire-none の注記参照）。
tier-tripwire:
	@TIER_TRIPWIRE_PATHS="" TIER_TRIPWIRE_SYMBOLS="" \
	 bash scripts/check-tier-tripwire.sh

# 整合性監査一式（詳細: docs/rules/consistency.md）
audit-all:
	@bash scripts/audit-consistency.sh

# git フック（pre-push・commit-msg）をローカルに導入する
install-hooks:
	@ln -sf ../../scripts/pre-push "$$(git rev-parse --git-dir)/hooks/pre-push"
	@ln -sf ../../scripts/commit-msg "$$(git rev-parse --git-dir)/hooks/commit-msg"
	@chmod +x scripts/pre-push scripts/commit-msg
	@echo "[install-hooks] ✅ pre-push・commit-msg フックを導入しました"
