# AI Dev Foundation — 品質ゲートの入口（docs/rules/quality-gates.md の Makefile ターゲット契約）
# フック・CI・人間が同じ入口を共有するための規約ターゲット。
# この基盤リポジトリはアプリコードを持たないため、test はプレースホルダ、
# 実質的なゲートは audit-all（ドキュメント/テンプレートの整合性監査）が担う。

.PHONY: all test lint audit-all install-hooks

all: audit-all test

# 全テスト実行。基盤リポジトリにはアプリの単体テストが無いため、
# ここでは監査スクリプトの自己検査（構文チェック）のみ行い成功で返す。
# サービスリポジトリ側は各スタックのテストランナーで上書きする。
test:
	@echo "[test] このリポジトリにアプリ単体テストはありません。監査スクリプトの構文を検査します。"
	@bash -n scripts/audit-consistency.sh
	@bash -n scripts/pre-push
	@echo "[test] ✅ 構文チェック通過"

# 静的解析。shellcheck があればスクリプトを検査し、無ければスキップ（ゼロ警告ゲート）。
lint:
	@if command -v shellcheck >/dev/null 2>&1; then \
		echo "[lint] shellcheck を実行中..."; \
		shellcheck scripts/*.sh scripts/pre-push || exit 1; \
		echo "[lint] ✅ 警告なし"; \
	else \
		echo "[lint] shellcheck 未導入のためスキップ（導入推奨: apt-get install shellcheck）"; \
	fi

# 整合性監査一式（詳細: docs/rules/consistency.md）
audit-all:
	@bash scripts/audit-consistency.sh

# git フック（pre-push）をローカルに導入する
install-hooks:
	@ln -sf ../../scripts/pre-push "$$(git rev-parse --git-dir)/hooks/pre-push"
	@chmod +x scripts/pre-push
	@echo "[install-hooks] ✅ pre-push フックを導入しました（.git/hooks/pre-push → scripts/pre-push）"
