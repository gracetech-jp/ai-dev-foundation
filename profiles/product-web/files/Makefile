# SERVICE_NAME — 品質ゲートの入口（product-web プロファイル実装。docs/rules/quality-gates.md の Makefile ターゲット契約）
# フック・CI・人間が同じ入口を共有するための規約ターゲット。
# スタック: Python 3.14 + uv + FastAPI + PostgreSQL（compose 別コンテナ）。初期状態は full-red（ADR-006 §7.2）:
#   ゲートは実コマンドで実装済みだが、生成直後は空プロジェクトのため自然に赤になる
#   （テスト0件は pytest が exit 5 ／ tier-tripwire は機微定義まで exit 2）。TODO+exit 1 の「偽の赤」ではない。
#   display-green のような skip 緑の条件分岐は入れない。

.PHONY: all test lint coverage req-coverage tier-tripwire audit-all audit-deps install-hooks

all: audit-all test req-coverage tier-tripwire

# 全テスト実行。テスト0件は pytest が exit 5 ＝ テストを書くまで赤（実装強制。full-red）。
test:
	@uv run pytest

# 静的解析（ruff・ゼロ警告）。実コード上クリーンで緑になるのは正当な実判定（ADR-006 §7）。
lint:
	@uv run ruff check .

# カバレッジのフロア検証（一方向ラチェット。quality-gates.md §5）。
# テスト0件は coverage run が exit 5 ＝ 赤。テスト導入後は実測値がフロア判定に渡り、床を引き上げていく。
coverage:
	@uv run coverage run -m pytest && uv run coverage report --format=total | xargs bash scripts/check-coverage.sh

# 依存パッケージの脆弱性監査（docs/rules/security.md）。プロジェクト環境を pip-audit で監査する。
audit-deps:
	@uv run --with pip-audit pip-audit

# 要件↔テストのカバレッジ・妥当性・改変検知（docs/rules/requirements.md / testing.md）。
# Python 系のマーカー走査デフォルト（要件0件なら緑＝設定は実装であり fail-open ではない。要件を持った時点から実検証）。
req-coverage:
	@REQ_TEST_PATHS="tests" \
	 REQ_MARKER_RE='@req:?[[:space:]]*R-[0-9]+' \
	 ADV_MARKER_RE='@adversarial:?[[:space:]]*R-[0-9]+' \
	 REQ_COMMENT_PREFIX='#' \
	 bash scripts/check-requirements-coverage.sh

# Tierトリップワイヤ（docs/rules/tiers.md）。product-web は .tier-tripwire-none を同梱しない＝
# 機微パターンの定義（SERVICE.md「Tierトリップワイヤ設定」）か、真に機微が無い場合の人間 commit 宣言まで
# exit 2 で赤（fail-closed）。動的アプリは機微を持つのが常のため、これが実装強制の本領。
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
