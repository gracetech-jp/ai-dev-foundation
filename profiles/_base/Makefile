# [サービス名] — 品質ゲートの入口（docs/rules/quality-gates.md の Makefile ターゲット契約）
# フック・CI・人間が同じ入口を共有するための規約ターゲット。
# 中身は各サービスのスタックに合わせて実装すること（この雛形は最小構成）。

.PHONY: all test lint coverage req-coverage tier-tripwire audit-all audit-deps install-hooks

all: audit-all test req-coverage tier-tripwire

# 未実装(TODO)ターゲットは exit 3 を返す（CI 契約: docs/rules/quality-gates.md §4）。
# CI の gates ジョブは make のエラー行「Error 3」で TODO を構造的に識別し soft（警告のみ）扱いにする。
# 実装したら exit 3 行ごと削除する＝以後の失敗は本物の違反として red になる。
# ※ req-coverage の未設定だけは exit 3 にしない（要件トレーサビリティは fail-closed を維持し無条件 red）。

# 全テスト実行。各スタックのテストランナーに置き換える（例: npm test / pytest）。
test:
	@echo "[test] TODO: このサービスのテストコマンドを設定してください（例: npm test）"
	@exit 3

# 静的解析。ゼロ警告ゲート（警告が出たら失敗させる設定にする。例: eslint --max-warnings=0）。
lint:
	@echo "[lint] TODO: このサービスの静的解析コマンドを設定してください（例: npm run lint）"
	@exit 3

# カバレッジのフロア検証（一方向ラチェット。詳細: docs/rules/quality-gates.md §5）。
# カバレッジを計測し、測定値を scripts/check-coverage.sh に渡してフロア割れを失敗させる。
coverage:
	@echo "[coverage] TODO: カバレッジを計測し scripts/check-coverage.sh に測定値を渡してください"
	@echo "         例: bash scripts/check-coverage.sh <測定カバレッジ%>"
	@exit 3

# 要件↔テストのカバレッジ検証（詳細: docs/rules/requirements.md / testing.md）。
# マーカー走査設定はスタック依存。このサービスの構成に合わせて env を設定して実行する。
# 未設定のまま実行すると check-requirements-coverage.sh が exit 2（fail-closed）で失敗する。
req-coverage:
	@echo "[req-coverage] TODO: このサービスのマーカー走査設定を行ってください（docs/rules/testing.md / requirements.md）。"
	@echo "         設定して実行: REQ_TEST_PATHS=<テストパス> REQ_MARKER_RE=<reqマーカー正規表現> \\"
	@echo "                       [ADV_MARKER_RE=<advマーカー正規表現>] \\"
	@echo "                       bash scripts/check-requirements-coverage.sh"
	@exit 1

# Tierトリップワイヤ（詳細: docs/rules/tiers.md / SERVICE.md「Tierトリップワイヤ設定」）。
# 機微パターンをこのサービスの値に設定する（TIER_TRIPWIRE_PATHS / TIER_TRIPWIRE_SYMBOLS）。
# 空のまま かつ docs/requirements/.tier-tripwire-none 不在は exit 2（fail-closed）。
# 機微面が無いサービスは .tier-tripwire-none をコミットして明示宣言する。
tier-tripwire:
	@TIER_TRIPWIRE_PATHS="" TIER_TRIPWIRE_SYMBOLS="" \
	 bash scripts/check-tier-tripwire.sh

# 整合性監査一式（詳細: docs/rules/consistency.md）
audit-all:
	@bash scripts/audit-consistency.sh

# 依存パッケージの脆弱性監査（詳細: docs/rules/security.md）。
audit-deps:
	@echo "[audit-deps] TODO: 依存の脆弱性監査コマンドを設定してください（例: npm audit --audit-level=high / pip-audit）"
	@exit 3

# git フック（pre-push・commit-msg）をローカルに導入する
install-hooks:
	@ln -sf ../../scripts/pre-push "$$(git rev-parse --git-dir)/hooks/pre-push"
	@ln -sf ../../scripts/commit-msg "$$(git rev-parse --git-dir)/hooks/commit-msg"
	@chmod +x scripts/pre-push scripts/commit-msg
	@echo "[install-hooks] ✅ pre-push・commit-msg フックを導入しました"
