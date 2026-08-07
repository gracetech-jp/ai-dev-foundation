# AI Dev Foundation — 品質ゲートの入口（docs/rules/quality-gates.md の Makefile ターゲット契約）
# フック・CI・人間が同じ入口を共有するための規約ターゲット。
# この基盤リポジトリはアプリコードを持たないが、配布するシェル資産（ガードレール等）を
# bats で自己検証する。test は「スクリプト構文チェック + bats シェルテスト」を担い、
# audit-all（ドキュメント/テンプレートの整合性監査）と二本立てで品質を担保する。

.PHONY: all test lint coverage req-coverage tier-tripwire audit-all audit-deps install-hooks

all: audit-all test req-coverage tier-tripwire

# 全テスト実行。まず配布シェル資産の構文を検査し、続いて bats でガードレール等の挙動を検証する。
# bats 不在は fail-closed（黙ってスキップするとシェル資産のゲートが形骸化するため。lint と同方針）。
# devcontainer には Dockerfile で、CI には ubuntu ランナーの apt で導入する。
# サービスリポジトリ側は各スタックのテストランナーで上書きする（bats は基盤の dogfood 専用）。
test:
	@echo "[test] 配布シェル資産の構文を検査します。"
	@for f in scripts/*.sh .claude/scripts/*.sh profiles/_base/scripts/*.sh profiles/_base/.devcontainer/postCreate.sh common/scripts/*.sh common/scripts/pre-push common/scripts/commit-msg service-templates/scripts/*.sh service-templates/.devcontainer/postCreate.sh .github/actions/*/*.sh; do bash -n "$$f" || exit 1; done
	@command -v bats >/dev/null 2>&1 || { echo "[test] ❌ bats が見つかりません（fail-closed。導入: apt-get install bats）"; exit 1; }
	@echo "[test] bats を実行中..."
	@bats tests/
	@echo "[test] ✅ 構文チェック + bats 通過"

# 静的解析（ゼロ警告ゲート）。shellcheck 不在は fail-closed（黙ってスキップするとゲートが形骸化するため）。
# devcontainer には Dockerfile で導入済み。CI の ubuntu ランナーにもプリインストールされている。
lint:
	@command -v shellcheck >/dev/null 2>&1 || { echo "[lint] ❌ shellcheck が見つかりません（fail-closed。導入: apt-get install shellcheck）"; exit 1; }
	@echo "[lint] shellcheck を実行中..."
	@shellcheck scripts/*.sh .claude/scripts/*.sh profiles/_base/scripts/*.sh profiles/_base/.devcontainer/postCreate.sh common/scripts/*.sh common/scripts/pre-push common/scripts/commit-msg common/docker/*.sh service-templates/scripts/*.sh service-templates/.devcontainer/postCreate.sh .github/actions/*/*.sh || exit 1
	@echo "[lint] ✅ 警告なし"

# カバレッジのフロア検証（ラチェット）。基盤リポはアプリコードが無いためスキップ。
# サービス側はカバレッジを計測し common/scripts/check-coverage.sh に測定値を渡して失敗判定する。
coverage:
	@echo "[coverage] 基盤リポにカバレッジ対象のアプリコードはありません。スキップします。"

# 要件↔テストのカバレッジ検証（詳細: docs/rules/requirements.md / testing.md）。
# 基盤は bats テストにコメントマーカー（# @req: R-xxx / # @adversarial: R-xxx）で要件を紐づける。
# マーカー走査設定はスタック依存のため env で渡す（サービス側は PROJECT.md 由来の値を Makefile で設定）。
req-coverage:
	@REQ_TEST_PATHS="tests" \
	 REQ_MARKER_RE='@req:?[[:space:]]*R-[0-9]+' \
	 ADV_MARKER_RE='@adversarial:?[[:space:]]*R-[0-9]+' \
	 bash common/scripts/check-requirements-coverage.sh "$(CURDIR)"

# Tierトリップワイヤ（Tier デスカレーションをコード実態から裏取り。詳細: docs/rules/tiers.md）。
# 基盤 ai-dev-foundation はアプリの機微プロダクトコードを持たないが、**配布するガードレール自身**が
# この基盤の機微面である（破壊的操作の遮断＝R-001、共通所有ファイルの封鎖＝R-002、
# 外向き通信の許可宛先＝R-003。いずれも Tier-S・ratified）。
# 空設定＋「機微面なし」宣言では F2 も S4 も一度も走らず ADR-008「維持したもの」と矛盾するため、
# 機微パスを R-001・R-002・R-003 の paths の和集合として明示する（2026-07-25 是正 / 2026-08-04 R-003 追加）。
# R-003 の分（init-firewall.sh と許可ドメインの追加リスト）を入れるのは、ADR-012 で「本物の境界は
# コンテナ隔離だけ」と決めた以上、外へ出られる宛先の集合そのものが爆発半径を決めるため。
# ここを黙って1行足せる状態は、境界を無審査で広げられる状態と同じである（ADR-013 結果節）。
# シンボルを空にするのは、基盤の機微面がファイル単位で確定しており、シンボル走査は統べる要件を
# 持たないファイル（bats 等）を巻き込んで偽陽性を生むだけだから。サービス側は PROJECT.md 由来の値を渡す。
tier-tripwire:
	@TIER_TRIPWIRE_PATHS='.claude/scripts/guard-dangerous.sh|.claude/settings.json|profiles/_base/.claude/settings.json|profiles/*/files/.claude/settings.json|service-templates/claude/settings.json|common/docker/init-firewall.sh|profiles/_base/.devcontainer/init-firewall.sh|service-templates/.devcontainer/init-firewall.sh|.devcontainer/init-firewall.sh|.devcontainer/extra-allowed-domains.txt|profiles/*/files/.devcontainer/extra-allowed-domains.txt' \
	 TIER_TRIPWIRE_SYMBOLS="" \
	 bash common/scripts/check-tier-tripwire.sh "$(CURDIR)"

# 整合性監査一式（詳細: docs/rules/consistency.md）
audit-all:
	@bash scripts/audit-consistency.sh

# 依存パッケージの脆弱性監査。基盤リポは外部ランタイム依存が無いためスキップ。
audit-deps:
	@echo "[audit-deps] 基盤リポに外部ランタイム依存はありません。スキップします。"

# git フック（pre-push・commit-msg）をローカルに導入する。
# 基盤リポも各プロジェクトと同じ形で common/scripts/ を参照する（複製を持たない。ADR-010）。
# 相対リンク（-r）と --git-common-dir の理由は common/make/contract.mk の同名ターゲットに書いた。
# 基盤リポ自身も 2026-08-07 まで絶対リンクで、ホストからは1回も走らない状態だった。
install-hooks:
	@hooks="$$(git -C "$(CURDIR)" rev-parse --path-format=absolute --git-common-dir)/hooks"; \
	 ln -sfr "$(CURDIR)/common/scripts/pre-push"   "$$hooks/pre-push"; \
	 ln -sfr "$(CURDIR)/common/scripts/commit-msg" "$$hooks/commit-msg"; \
	 echo "[install-hooks] ✅ pre-push / commit-msg を common/scripts/ へ相対リンクしました（$$hooks）"
