# contract.mk — 品質ゲートの Makefile ターゲット契約（共通・スタック中立）。
# 各プロジェクトの Makefile が include して使う。中身の実装はプロジェクト側が書く。
#
# 使い方（プロジェクト側 Makefile の冒頭）:
#   PROJECT_ROOT := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
#   COMMON_ROOT  := $(shell ...マーカー探索...)
#   include $(COMMON_ROOT)/common/make/contract.mk
#   include $(COMMON_ROOT)/common/make/gates.mk
#
# 契約の正: docs/rules/quality-gates.md「Makefile ターゲット契約」

# 契約ターゲット。プロジェクト側が実装しなかったターゲットは make が
# 「No rule to make target」で失敗する＝黙って通らない（fail-closed）。
.PHONY: all test lint coverage req-coverage tier-tripwire audit-all audit-deps install-hooks

# 既定ターゲット。lint / coverage / audit-deps は各スタックの整備状況に依存するため
# ここでは束ねない（束ねると未整備のプロジェクトで all が常に赤になる）。
all: audit-all test req-coverage tier-tripwire

# git フック（pre-push・commit-msg）をローカルに導入する。
# 実体は共通側に置き、プロジェクトにはコピーを残さない（参照方式）。
install-hooks:
	@hooks="$$(git -C "$(PROJECT_ROOT)" rev-parse --git-dir)/hooks"; \
	 ln -sf "$(COMMON_ROOT)/common/scripts/pre-push"   "$$hooks/pre-push"; \
	 ln -sf "$(COMMON_ROOT)/common/scripts/commit-msg" "$$hooks/commit-msg"; \
	 echo "[install-hooks] ✅ pre-push / commit-msg を共通側へリンクしました"
