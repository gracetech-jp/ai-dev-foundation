#!/usr/bin/env bats
# new-service.sh のプロファイル合成（ADR-006 フェーズ1）の回帰。
# 生成先は「共通基盤の projects/ 配下」固定のため、基盤の複製をテスト毎に作って隔離する。
# 要件マーカーは付けない（未登録IDのマーカーは check-requirements-coverage.sh の
# dangling 検出で赤になるため。要件化は要件ファイルを ratified で起こしてから行う）。

setup() {
	REPO="$BATS_TEST_DIRNAME/.."
	export HOME="$BATS_TEST_TMPDIR/home"
	mkdir -p "$HOME"
	# 参照方式では生成先が「共通基盤の projects/ 配下」でなければマーカーを解決できない。
	# 実リポの projects/ を汚さないため、基盤の最小複製をサンドボックスに作りそこから生成する
	# （$ROOT はスクリプト位置から決まるので、複製から起動すれば生成先も複製配下になる）。
	FSB="$BATS_TEST_TMPDIR/foundation"
	mkdir -p "$FSB/scripts"
	cp "$REPO/scripts/new-service.sh" "$FSB/scripts/"
	cp -a "$REPO/profiles" "$FSB/profiles"
	cp -a "$REPO/common" "$FSB/common"
	cp "$REPO/.ai-dev-foundation-root" "$FSB/"
	SUT="$FSB/scripts/new-service.sh"
	PROJ="$FSB/projects"
}

ns() { bash "$SUT" "$@"; }

# manifest 異常系用サンドボックス：リポの配布ソース一式を最小構成で複製し、
# 実リポの working tree を汚さずに manifest を破壊できるようにする。
make_sandbox() {
	SB="$BATS_TEST_TMPDIR/sb"
	mkdir -p "$SB/scripts" "$SB/docs/rules"
	cp "$SUT" "$SB/scripts/"
	cp -a "$REPO/profiles" "$SB/profiles"
	cp "$REPO/CLAUDE.md" "$SB/"
	cp "$REPO/docs/rules/"*.md "$SB/docs/rules/"
	# 共通スクリプトは複製しない（2026-07-30 順輸入廃止・ADR-010。実体は common/scripts/）
	cp -a "$REPO/common" "$SB/common"
	cp "$REPO/.ai-dev-foundation-root" "$SB/"
}

# ---- 緑: 正常系 ----

@test "緑: --profile product-static で生成成功し骨格一式が存在する" {
	run ns svc1 --profile product-static
	[ "$status" -eq 0 ]
	T="$PROJ/svc1"
	# repo-layout.md「必須ファイル / ディレクトリ」との突合（配布漏れなし）
	for f in PROJECT.md README.md Makefile .editorconfig .env.example .gitignore \
		.coverage-floor .req-coverage-baseline .tier-tripwire-allow \
		.devcontainer/Dockerfile .devcontainer/devcontainer.json .devcontainer/postCreate.sh \
		.claude/settings.json .claude/scripts/guard-dangerous.sh .claude/scripts/session-start-rules.sh \
		.github/workflows/ci.yml \
		scripts/audit-consistency.sh \
		docs/requirements/R-000-template.md docs/service-rules/consistency.md docs/decisions/README.md; do
		[ -e "$T/$f" ]
	done
	# 逆輸入の廃止（ADR-009）: 逆輸入ツールは配布しない
	[ ! -e "$T/scripts/backport-to-common.sh" ]
	# 順輸入の廃止（ADR-010）: マニフェスト・順輸入ツールも配布しない
	[ ! -e "$T/.backport-manifest" ]
	[ ! -e "$T/scripts/sync-from-common.sh" ]
	# 参照方式: 共通所有の実体は共通リポにのみ置き、複製を配らない。
	# 「複製が生えていないこと」を明示的に検査する（配らない判断が退化したら赤にする）。
	[ ! -e "$T/CLAUDE.md" ]
	[ ! -e "$T/docs/rules" ]
	for s in pre-push commit-msg check-coverage.sh check-requirements-coverage.sh check-tier-tripwire.sh; do
		[ ! -e "$T/scripts/$s" ]
	done
}

@test "緑: product-static の replace/add が反映される" {
	run ns svc2 --profile product-static
	[ "$status" -eq 0 ]
	T="$PROJ/svc2"
	grep -q "profile:product-static" "$T/.devcontainer/Dockerfile"
	[ "$(cat "$T/.service-profile")" = "product-static" ]
}

@test "緑: product-web の replace/add が反映され product-static と取り違えない" {
	run ns svc3 --profile product-web
	[ "$status" -eq 0 ]
	T="$PROJ/svc3"
	grep -q "profile:product-web" "$T/.devcontainer/Dockerfile"
	! grep -q "profile:product-static" "$T/.devcontainer/Dockerfile"
	[ "$(cat "$T/.service-profile")" = "product-web" ]
	# フェーズ3本実装分: compose・pyproject・参照実装・.python-version が配布される
	[ -f "$T/.devcontainer/compose.yaml" ]
	[ -f "$T/pyproject.toml" ]
	[ -f "$T/app/main.py" ]
	[ -f "$T/.python-version" ]
}

@test "緑: SERVICE_NAME 置換が base 由来とプロファイル由来の双方に効く" {
	run ns svc4 --profile product-static
	[ "$status" -eq 0 ]
	T="$PROJ/svc4"
	grep -q "svc4" "$T/.devcontainer/devcontainer.json"   # base 由来（sed 生成）
	grep -q "svc4" "$T/PROJECT.md"                        # base 由来（[サービス名] 置換）
	grep -q "service: svc4" "$T/.devcontainer/Dockerfile" # profile 由来（合成後の置換パス）
	! grep -q "SERVICE_NAME" "$T/.devcontainer/Dockerfile"
}

# ---- 赤: fail-closed 恒久回帰 ----

@test "赤: プロファイル未指定は exit 1 で利用可能一覧を表示する" {
	run ns svc5
	[ "$status" -eq 1 ]
	[[ "$output" == *"product-static"* ]]
	[[ "$output" == *"product-web"* ]]
}

@test "赤: --profile _base の明示指定は exit 1（内部部品。ADR-006 §6）" {
	run ns svc6 --profile _base
	[ "$status" -eq 1 ]
}

@test "赤: 存在しないプロファイル名は exit 1 で一覧を表示する" {
	run ns svc7 --profile no-such-profile
	[ "$status" -eq 1 ]
	[[ "$output" == *"product-static"* ]]
}

@test "赤: サービス名のパストラバーサルは exit 1（既存バリデーション維持）" {
	run ns "../evil" --profile product-static
	[ "$status" -eq 1 ]
	[ ! -e "$HOME/evil" ]
}

@test "赤: 生成先が既に存在すれば exit 1（既存バリデーション維持）" {
	mkdir -p "$PROJ/svc9"
	run ns svc9 --profile product-static
	[ "$status" -eq 1 ]
}

@test "赤: manifest の未知 op は exit 2（fail-closed）" {
	make_sandbox
	echo "frobnicate some/path" >> "$SB/profiles/product-static/profile.manifest"
	run bash "$SB/scripts/new-service.sh" svc10 --profile product-static
	[ "$status" -eq 2 ]
}

@test "赤: manifest 記載の files/ 実体欠落は exit 2（fail-closed）" {
	make_sandbox
	echo "add ghost.txt" >> "$SB/profiles/product-static/profile.manifest"
	run bash "$SB/scripts/new-service.sh" svc11 --profile product-static
	[ "$status" -eq 2 ]
}

@test "廃止回帰: 生成物に CODEOWNERS を配布しない（批准レス化・ADR-008）" {
	run ns svc12 --profile product-static
	[ "$status" -eq 0 ]
	[ ! -e "$PROJ/svc12/.github/CODEOWNERS" ]
}

# ---- フェーズ2: display-green / failclosed_profile（ADR-006 §7.2） ----

@test "緑: product-static 生成直後に display-green ゲート一式（test/lint/coverage/req-coverage/tier-tripwire）が緑" {
	run ns svd1 --profile product-static
	[ "$status" -eq 0 ]
	T="$PROJ/svd1"
	for t in test lint coverage req-coverage tier-tripwire; do
		run make -C "$T" "$t"
		[ "$status" -eq 0 ]
	done
	# 黙って通さない: skip には理由の警告が付く（空虚な緑を潰す思想）
	run make -C "$T" test
	[[ "$output" == *"package.json"* ]]
}

@test "緑: product-static 生成物に .tier-tripwire-none が同梱されプレースホルダ置換も効く" {
	run ns svd2 --profile product-static
	[ "$status" -eq 0 ]
	F="$PROJ/svd2/docs/requirements/.tier-tripwire-none"
	[ -f "$F" ]
	grep -q "svd2" "$F"
	! grep -q "SERVICE_NAME" "$F"
}

@test "赤維持: product-web は full-red（生成直後 test と tier-tripwire が赤。ADR-006 §7）" {
	run ns svd3 --profile product-web
	[ "$status" -eq 0 ]
	T="$PROJ/svd3"
	# test: 実コマンド（uv run pytest）。テスト0件（またはツール未導入環境）で非0＝実装するまで赤
	run make -C "$T" test
	[ "$status" -ne 0 ]
	# tier-tripwire: .tier-tripwire-none を同梱しない＝機微定義まで exit 2（fail-closed）
	[ ! -e "$T/docs/requirements/.tier-tripwire-none" ]
	run make -C "$T" tier-tripwire
	[ "$status" -ne 0 ]
	# display-green の skip 緑分岐が混入していないこと（黙のスキップ禁止）
	! grep -q "skip（display-green）" "$T/Makefile"
}

@test "境界: product-web の参照実装は /health のみ・ドメイン構造ゼロ（ADR-006 §3.1）" {
	run ns svd6 --profile product-web
	[ "$status" -eq 0 ]
	T="$PROJ/svd6"
	# ルート定義は /health の1本のみ（業務エンドポイントを配らない）
	routes=$(grep -rE '@app\.(get|post|put|delete|patch)' "$T/app/")
	[ "$(echo "$routes" | wc -l)" -eq 1 ]
	echo "$routes" | grep -q '"/health"'
	# SQL は SELECT 1（疎通確認）のみ。テーブル定義・マイグレーションは存在しない
	! grep -rniE 'CREATE TABLE|alembic|migrat' "$T/app/" "$T/pyproject.toml" "$T/.devcontainer/compose.yaml"
}

@test "赤: manifest の failclosed_profile 不正値（all-green 等）は exit 2" {
	make_sandbox
	sed -i 's/^failclosed_profile: display-green/failclosed_profile: all-green/' "$SB/profiles/product-static/profile.manifest"
	run bash "$SB/scripts/new-service.sh" svd4 --profile product-static
	[ "$status" -eq 2 ]
}

@test "赤: manifest の failclosed_profile 欠落は exit 2（分類し忘れ防止）" {
	make_sandbox
	sed -i '/^failclosed_profile:/d' "$SB/profiles/product-static/profile.manifest"
	run bash "$SB/scripts/new-service.sh" svd5 --profile product-static
	[ "$status" -eq 2 ]
}
