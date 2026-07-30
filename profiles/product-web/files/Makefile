# SERVICE_NAME — 品質ゲートの入口（product-web プロファイル実装。docs/rules/quality-gates.md の Makefile ターゲット契約）
# フック・CI・人間が同じ入口を共有するための規約ターゲット。
# スタック: Python 3.14 + uv + FastAPI + PostgreSQL（compose 別コンテナ）。初期状態は full-red（ADR-006 §7.2）:
#   ゲートは実コマンドで実装済みだが、生成直後は空プロジェクトのため自然に赤になる
#   （テスト0件は pytest が exit 5 ／ tier-tripwire は機微定義まで exit 2）。TODO+exit 1 の「偽の赤」ではない。
#   display-green のような skip 緑の条件分岐は入れない。

# 参照方式（2026-07-30 順輸入廃止・ADR-010）: 共通のゲート実装はこのリポジトリに複製せず、
# 共通基盤リポジトリの common/make/*.mk と common/scripts/ を参照する。
# 解決の起点はマーカー .ai-dev-foundation-root（上方向に探索）。

PROJECT_ROOT := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))

COMMON_ROOT := $(shell d="$(PROJECT_ROOT)"; while [ "$$d" != "/" ]; do \
                   [ -f "$$d/.ai-dev-foundation-root" ] && { echo "$$d"; break; }; \
                   d=$$(dirname "$$d"); done)

# 見つからなければ即エラー（fail-closed）。黙って「ゲート無しで緑」にしないこと。
ifeq ($(COMMON_ROOT),)
$(error 共通基盤のルート(.ai-dev-foundation-root)が見つかりません。このリポジトリが共通基盤リポジトリの配下に置かれているか、devcontainer のマウント設定を確認してください)
endif

# ---- 共通ゲートの取り込み（ターゲット契約 all / install-hooks と、ゲート呼び出し） ----
include $(COMMON_ROOT)/common/make/contract.mk
include $(COMMON_ROOT)/common/make/gates.mk

# ---- このサービスの設定（共通ゲートに渡す値） ----
# Python 系のマーカー走査デフォルト（要件0件なら緑＝設定は実装であり fail-open ではない。要件を持った時点から実検証）。
REQ_TEST_PATHS        := tests
REQ_MARKER_RE         := @req:?[[:space:]]*R-[0-9]+
ADV_MARKER_RE         := @adversarial:?[[:space:]]*R-[0-9]+

# product-web は .tier-tripwire-none を同梱しない＝機微パターンの定義（PROJECT.md「Tierトリップワイヤ設定」）か、
# 真に機微が無い場合の .tier-tripwire-none 宣言まで exit 2 で赤（fail-closed）。
# 動的アプリは機微を持つのが常のため、これが実装強制の本領。
TIER_TRIPWIRE_PATHS   :=
TIER_TRIPWIRE_SYMBOLS :=

# 全テスト実行。テスト0件は pytest が exit 5 ＝ テストを書くまで赤（実装強制。full-red）。
test:
	@uv run pytest

# 静的解析（ruff・ゼロ警告）。実コード上クリーンで緑になるのは正当な実判定（ADR-006 §7）。
lint:
	@uv run ruff check .

# カバレッジのフロア検証（一方向ラチェット。quality-gates.md §5）。
# テスト0件は coverage run が exit 5 ＝ 赤。テスト導入後は実測値がフロア判定に渡り、床を引き上げていく。
# 比較の実体は共通側（gates.mk の coverage-floor → common/scripts/check-coverage.sh）。
coverage:
	@uv run coverage run -m pytest && \
	 $(MAKE) --no-print-directory coverage-floor \
	   COVERAGE_MEASURED="$$(uv run coverage report --format=total)"

# 依存パッケージの脆弱性監査（docs/rules/security.md）。プロジェクト環境を pip-audit で監査する。
audit-deps:
	@uv run --with pip-audit pip-audit

# 整合性監査一式（詳細: docs/rules/consistency.md）
audit-all:
	@bash scripts/audit-consistency.sh
