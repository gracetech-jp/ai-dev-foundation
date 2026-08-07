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
#
# 【-r（相対リンク）は必須である。2026-08-07 に絶対リンクで実害が出た】
# devcontainer 内で実行すると COMMON_ROOT はコンテナ内のパスに解決される。そのリンクは
# ホストのターミナルからは解決できず、**git は解決できないシンボリックリンクを「フックが無い」と
# 同じに扱う**ため、何のメッセージも出さずに素通りする。sumai-desk で pre-push が黙って
# 走らない状態が実際に発生した。相対なら、リポジトリが基盤の projects/ 配下にある限り
# （ADR-010 の前提）ホストでもコンテナでも同じ実体に解決される。
# 張られた結果が相対であることは check-git-hooks.sh が機械検査する。
#
# --git-common-dir を使うのは、worktree では --git-dir がワークツリー専用ディレクトリを返す
# 一方、git が読むのは共有側だから（専用側へ張ると1回も走らないフックができる）。
# --path-format=absolute を付けるのは、素の出力が呼び出し元の作業ディレクトリ基準の
# 相対パスになり、make -C やサブディレクトリからの実行で別の場所を指すため。
install-hooks:
	@hooks="$$(git -C "$(PROJECT_ROOT)" rev-parse --path-format=absolute --git-common-dir)/hooks"; \
	 ln -sfr "$(COMMON_ROOT)/common/scripts/pre-push"   "$$hooks/pre-push"; \
	 ln -sfr "$(COMMON_ROOT)/common/scripts/commit-msg" "$$hooks/commit-msg"; \
	 echo "[install-hooks] ✅ pre-push / commit-msg を共通側へ相対リンクしました（$$hooks）"
