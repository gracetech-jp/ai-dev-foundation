# SERVICE_NAME — 品質ゲートの入口（docs/rules/quality-gates.md の Makefile ターゲット契約）
# フック・CI・人間が同じ入口を共有するための規約ターゲット。
#
# 参照方式（2026-07-26 フェーズ1〜）: 共通のゲート実装はこのリポジトリに複製せず、
# 共通基盤リポジトリの common/make/*.mk と common/scripts/ を参照する。
# 解決の起点はマーカー .ai-dev-foundation-root（上方向に探索）。深さを仮定しないので
# ディレクトリ構成を変えても壊れない。

# このMakefile自身の位置からプロジェクトルートを決める（cwd に依存しない。make -C でも正しい）
PROJECT_ROOT := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))

# 共通基盤のルートをマーカーで解決する
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
# テスト探索パス。未設定だと req-coverage が fail-closed で失敗する。
REQ_TEST_PATHS        := tests
REQ_MARKER_RE         := @req:?[[:space:]]*R-[0-9]+
ADV_MARKER_RE         := @adversarial:?[[:space:]]*R-[0-9]+

# 機微コードのパス glob（| 区切り）。SERVICE.md「Tierトリップワイヤ設定」を正とする。
# 空のまま かつ docs/requirements/.tier-tripwire-none 不在は exit 2（fail-closed）。
# 機微面が無いサービスは .tier-tripwire-none をコミットして明示宣言する。
TIER_TRIPWIRE_PATHS   :=
TIER_TRIPWIRE_SYMBOLS :=

# ---- このサービスの実装（スタック依存。ここから下を埋める） ----
# 未実装(TODO)ターゲットは exit 3 を返す（CI 契約: docs/rules/quality-gates.md §4）。
# 実装したら exit 3 行ごと削除する＝以後の失敗は本物の違反として red になる。

# 全テスト実行。各スタックのテストランナーに置き換える（例: npm test / pytest）。
test:
	@echo "[test] TODO: このサービスのテストコマンドを設定してください（例: npm test）"
	@exit 3

# 静的解析。ゼロ警告ゲート（警告が出たら失敗させる設定にする。例: eslint --max-warnings=0）。
lint:
	@echo "[lint] TODO: このサービスの静的解析コマンドを設定してください（例: npm run lint）"
	@exit 3

# カバレッジ計測。計測値を COVERAGE_MEASURED に入れて共通の coverage-floor を呼ぶ。
# 例: coverage: ; @COVERAGE_MEASURED=$$(...) $(MAKE) coverage-floor
coverage:
	@echo "[coverage] TODO: カバレッジを計測し、COVERAGE_MEASURED=<測定値> make coverage-floor を呼んでください"
	@exit 3

# 依存パッケージの脆弱性監査（詳細: docs/rules/security.md）。
audit-deps:
	@echo "[audit-deps] TODO: 依存の脆弱性監査コマンドを設定してください（例: npm audit --audit-level=high / pip-audit）"
	@exit 3

# 整合性監査一式（枠は共通、検査の中身はこのサービスが肉付けする。詳細: docs/rules/consistency.md）
audit-all:
	@bash scripts/audit-consistency.sh
