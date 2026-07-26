# gates.mk — 共通ゲートの呼び出し（共通・スタック中立）。
# スクリプトの実体は共通リポジトリの common/scripts/ にあり、各プロジェクトは複製を持たない。
# 検証対象のリポジトリルートは常に $(PROJECT_ROOT) を明示的に渡す（cwd に依存させない）。
#
# プロジェクト側 Makefile が定義すべき変数:
#   REQ_TEST_PATHS       … テスト探索パス（空白区切り）。未定義だと req-coverage が fail-closed で落ちる
#   TIER_TRIPWIRE_PATHS  … 機微コードのパス glob（| 区切り）
#   TIER_TRIPWIRE_SYMBOLS… 機微識別子の拡張正規表現（任意）
#   COVERAGE_MEASURED    … coverage ターゲットが計測した値（プロジェクト側の coverage が渡す）

# 要件↔テストのトレーサビリティ（詳細: docs/rules/requirements.md / testing.md）
req-coverage:
	@REQ_TEST_PATHS="$(REQ_TEST_PATHS)" \
	 REQ_MARKER_RE="$(REQ_MARKER_RE)" \
	 ADV_MARKER_RE="$(ADV_MARKER_RE)" \
	 bash "$(COMMON_ROOT)/common/scripts/check-requirements-coverage.sh" "$(PROJECT_ROOT)"

# Tier デスカレーションの裏取り（詳細: docs/rules/tiers.md）
tier-tripwire:
	@TIER_TRIPWIRE_PATHS='$(TIER_TRIPWIRE_PATHS)' \
	 TIER_TRIPWIRE_SYMBOLS='$(TIER_TRIPWIRE_SYMBOLS)' \
	 TIER_TRIPWIRE_SELF_RE='$(TIER_TRIPWIRE_SELF_RE)' \
	 bash "$(COMMON_ROOT)/common/scripts/check-tier-tripwire.sh" "$(PROJECT_ROOT)"

# カバレッジのフロア検証（一方向ラチェット。詳細: docs/rules/quality-gates.md §5）。
# 測定はプロジェクト側の責務。ここは受け取った値をフロアと比較するだけ。
coverage-floor:
	@bash "$(COMMON_ROOT)/common/scripts/check-coverage.sh" "$(COVERAGE_MEASURED)" "$(PROJECT_ROOT)"
