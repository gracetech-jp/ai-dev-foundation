# [サービス名] — 品質ゲートの入口（docs/rules/quality-gates.md の Makefile ターゲット契約）
# フック・CI・人間が同じ入口を共有するための規約ターゲット。
# 中身は各サービスのスタックに合わせて実装すること（この雛形は最小構成）。

.PHONY: all test lint coverage audit-all audit-deps install-hooks

all: audit-all test

# 全テスト実行。各スタックのテストランナーに置き換える（例: npm test / pytest）。
test:
	@echo "[test] TODO: このサービスのテストコマンドを設定してください（例: npm test）"
	@exit 1

# 静的解析。ゼロ警告ゲート（警告が出たら失敗させる設定にする。例: eslint --max-warnings=0）。
lint:
	@echo "[lint] TODO: このサービスの静的解析コマンドを設定してください（例: npm run lint）"
	@exit 1

# カバレッジのフロア検証（一方向ラチェット。詳細: docs/rules/quality-gates.md §5）。
# カバレッジを計測し、測定値を scripts/check-coverage.sh に渡してフロア割れを失敗させる。
coverage:
	@echo "[coverage] TODO: カバレッジを計測し scripts/check-coverage.sh に測定値を渡してください"
	@echo "         例: bash scripts/check-coverage.sh <測定カバレッジ%>"
	@exit 1

# 整合性監査一式（詳細: docs/rules/consistency.md）
audit-all:
	@bash scripts/audit-consistency.sh

# 依存パッケージの脆弱性監査（詳細: docs/rules/security.md）。
audit-deps:
	@echo "[audit-deps] TODO: 依存の脆弱性監査コマンドを設定してください（例: npm audit --audit-level=high / pip-audit）"
	@exit 1

# git フック（pre-push・commit-msg）をローカルに導入する
install-hooks:
	@ln -sf ../../scripts/pre-push "$$(git rev-parse --git-dir)/hooks/pre-push"
	@ln -sf ../../scripts/commit-msg "$$(git rev-parse --git-dir)/hooks/commit-msg"
	@chmod +x scripts/pre-push scripts/commit-msg
	@echo "[install-hooks] ✅ pre-push・commit-msg フックを導入しました"
