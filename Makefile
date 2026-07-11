# AI Dev Foundation — 品質ゲートの入口（docs/rules/quality-gates.md の Makefile ターゲット契約）
# フック・CI・人間が同じ入口を共有するための規約ターゲット。
# この基盤リポジトリはアプリコードを持たないため、test はプレースホルダ、
# 実質的なゲートは audit-all（ドキュメント/テンプレートの整合性監査）が担う。

.PHONY: all test lint coverage audit-all audit-deps install-hooks

all: audit-all test

# 全テスト実行。基盤リポジトリにはアプリの単体テストが無いため、
# ここでは監査スクリプトの自己検査（構文チェック）のみ行い成功で返す。
# サービスリポジトリ側は各スタックのテストランナーで上書きする。
test:
	@echo "[test] このリポジトリにアプリ単体テストはありません。スクリプトの構文を検査します。"
	@for f in scripts/*.sh scripts/pre-push scripts/commit-msg; do bash -n "$$f" || exit 1; done
	@echo "[test] ✅ 構文チェック通過"

# 静的解析。shellcheck があればスクリプトを検査し、無ければスキップ（ゼロ警告ゲート）。
lint:
	@if command -v shellcheck >/dev/null 2>&1; then \
		echo "[lint] shellcheck を実行中..."; \
		shellcheck scripts/*.sh scripts/pre-push scripts/commit-msg || exit 1; \
		echo "[lint] ✅ 警告なし"; \
	else \
		echo "[lint] shellcheck 未導入のためスキップ（導入推奨: apt-get install shellcheck）"; \
	fi

# カバレッジのフロア検証（ラチェット）。基盤リポはアプリコードが無いためスキップ。
# サービス側はカバレッジを計測し scripts/check-coverage.sh に測定値を渡して失敗判定する。
coverage:
	@echo "[coverage] 基盤リポにカバレッジ対象のアプリコードはありません。スキップします。"

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
