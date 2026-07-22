#!/usr/bin/env bats
# new-service.sh のプロファイル合成（ADR-006 フェーズ1）の回帰。
# 生成先は $HOME/projects 固定のため HOME をテスト毎に隔離する。
# 要件マーカーは付けない（未登録IDのマーカーは check-requirements-coverage.sh の
# dangling 検出で赤になるため。要件化は人間批准後に行う）。

setup() {
	REPO="$BATS_TEST_DIRNAME/.."
	SUT="$REPO/scripts/new-service.sh"
	export HOME="$BATS_TEST_TMPDIR/home"
	mkdir -p "$HOME"
}

ns() { bash "$SUT" "$@"; }

# manifest 異常系用サンドボックス：リポの配布ソース一式を最小構成で複製し、
# 実リポの working tree を汚さずに manifest を破壊できるようにする。
make_sandbox() {
	SB="$BATS_TEST_TMPDIR/sb"
	mkdir -p "$SB/scripts" "$SB/docs/rules"
	cp "$SUT" "$SB/scripts/"
	cp -a "$REPO/profiles" "$SB/profiles"
	cp "$REPO/CLAUDE.md" "$REPO/COMMAND.md" "$REPO/.backport-manifest" "$SB/"
	cp "$REPO/docs/rules/"*.md "$SB/docs/rules/"
	for s in pre-push commit-msg check-coverage.sh check-requirements-coverage.sh \
	         check-tier-tripwire.sh backport-to-common.sh sync-from-common.sh; do
		cp "$REPO/scripts/$s" "$SB/scripts/"
	done
}

# ---- 緑: 正常系 ----

@test "緑: --profile static-site で生成成功し骨格一式が存在する" {
	run ns svc1 --profile static-site
	[ "$status" -eq 0 ]
	T="$HOME/projects/svc1"
	# repo-layout.md「必須ファイル / ディレクトリ」との突合（配布漏れなし）
	for f in CLAUDE.md COMMAND.md SERVICE.md README.md Makefile .editorconfig .env.example .gitignore \
		.backport-manifest .coverage-floor .req-coverage-baseline .tier-tripwire-allow \
		.devcontainer/Dockerfile .devcontainer/devcontainer.json .devcontainer/postCreate.sh \
		.claude/settings.json .claude/scripts/guard-dangerous.sh .claude/scripts/session-start-rules.sh \
		.github/CODEOWNERS .github/workflows/ci.yml \
		scripts/pre-push scripts/commit-msg scripts/check-coverage.sh scripts/audit-consistency.sh \
		scripts/check-requirements-coverage.sh scripts/check-tier-tripwire.sh \
		scripts/backport-to-common.sh scripts/sync-from-common.sh \
		docs/requirements/R-000-template.md docs/service-rules/consistency.md docs/decisions/README.md; do
		[ -e "$T/$f" ]
	done
	[ -n "$(ls "$T/docs/rules/")" ]
}

@test "緑: static-site の replace/add が反映される" {
	run ns svc2 --profile static-site
	[ "$status" -eq 0 ]
	T="$HOME/projects/svc2"
	grep -q "profile:static-site" "$T/.devcontainer/Dockerfile"
	[ "$(cat "$T/.service-profile")" = "static-site" ]
}

@test "緑: web-app の replace/add が反映され static-site と取り違えない" {
	run ns svc3 --profile web-app
	[ "$status" -eq 0 ]
	T="$HOME/projects/svc3"
	grep -q "profile:web-app" "$T/.devcontainer/Dockerfile"
	! grep -q "profile:static-site" "$T/.devcontainer/Dockerfile"
	[ "$(cat "$T/.service-profile")" = "web-app" ]
}

@test "緑: SERVICE_NAME 置換が base 由来とプロファイル由来の双方に効く" {
	run ns svc4 --profile static-site
	[ "$status" -eq 0 ]
	T="$HOME/projects/svc4"
	grep -q "svc4" "$T/.devcontainer/devcontainer.json"   # base 由来（sed 生成）
	grep -q "svc4" "$T/SERVICE.md"                        # base 由来（[サービス名] 置換）
	grep -q "service: svc4" "$T/.devcontainer/Dockerfile" # profile 由来（合成後の置換パス）
	! grep -q "SERVICE_NAME" "$T/.devcontainer/Dockerfile"
}

# ---- 赤: fail-closed 恒久回帰 ----

@test "赤: プロファイル未指定は exit 1 で利用可能一覧を表示する" {
	run ns svc5
	[ "$status" -eq 1 ]
	[[ "$output" == *"static-site"* ]]
	[[ "$output" == *"web-app"* ]]
}

@test "赤: --profile _base の明示指定は exit 1（内部部品。ADR-006 §6）" {
	run ns svc6 --profile _base
	[ "$status" -eq 1 ]
}

@test "赤: 存在しないプロファイル名は exit 1 で一覧を表示する" {
	run ns svc7 --profile no-such-profile
	[ "$status" -eq 1 ]
	[[ "$output" == *"static-site"* ]]
}

@test "赤: サービス名のパストラバーサルは exit 1（既存バリデーション維持）" {
	run ns "../evil" --profile static-site
	[ "$status" -eq 1 ]
	[ ! -e "$HOME/evil" ]
}

@test "赤: 生成先が既に存在すれば exit 1（既存バリデーション維持）" {
	mkdir -p "$HOME/projects/svc9"
	run ns svc9 --profile static-site
	[ "$status" -eq 1 ]
}

@test "赤: manifest の未知 op は exit 2（fail-closed）" {
	make_sandbox
	echo "frobnicate some/path" >> "$SB/profiles/static-site/profile.manifest"
	run bash "$SB/scripts/new-service.sh" svc10 --profile static-site
	[ "$status" -eq 2 ]
}

@test "赤: manifest 記載の files/ 実体欠落は exit 2（fail-closed）" {
	make_sandbox
	echo "add ghost.txt" >> "$SB/profiles/static-site/profile.manifest"
	run bash "$SB/scripts/new-service.sh" svc11 --profile static-site
	[ "$status" -eq 2 ]
}
