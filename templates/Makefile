# [サービス名] — 品質ゲートの入口（docs/rules/quality-gates.md の Makefile ターゲット契約）
# フック・CI・人間が同じ入口を共有するための規約ターゲット。
# 中身は各サービスのスタックに合わせて実装すること（この雛形は最小構成）。

.PHONY: all test lint audit-all install-hooks

all: audit-all test

# 全テスト実行。各スタックのテストランナーに置き換える（例: npm test / pytest）。
test:
	@echo "[test] TODO: このサービスのテストコマンドを設定してください（例: npm test）"
	@exit 1

# 静的解析。ゼロ警告ゲート（警告が出たら失敗させる設定にする。例: eslint --max-warnings=0）。
lint:
	@echo "[lint] TODO: このサービスの静的解析コマンドを設定してください（例: npm run lint）"
	@exit 1

# 整合性監査一式（詳細: docs/rules/consistency.md）
audit-all:
	@bash scripts/audit-consistency.sh

# git フック（pre-push）をローカルに導入する
install-hooks:
	@ln -sf ../../scripts/pre-push "$$(git rev-parse --git-dir)/hooks/pre-push"
	@chmod +x scripts/pre-push
	@echo "[install-hooks] ✅ pre-push フックを導入しました"
