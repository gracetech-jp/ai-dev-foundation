#!/usr/bin/env bats
# 側置き配置（ADR-011 の CI レイアウト）でパス解決が成立することの固定資産テスト。
#
# CI では共通基盤を GITHUB_WORKSPACE 直下へ、プロジェクトを projects/<name> へチェックアウトし、
# **ローカル（devcontainer）と同じ位置関係**を再現する。これが崩れるとプロジェクトの Makefile が
# マーカー .ai-dev-foundation-root を見つけられず、COMMON_ROOT のガードが fail-closed で止まる
# （＝現在の CI で make を使えない理由そのもの。grace-tech-hp が実際にこれで make を諦めている）。
#
# ここで固定するのは2方向:
#   1. 側置きなら解決する（CI がこの配置を作れば make が使える）
#   2. 側置きでなければ**止まる**（黙ってゲート無しで緑にならない）
#
# @req: R-001
# @adversarial: R-001

setup() {
	REPO="$BATS_TEST_DIRNAME/.."
	export HOME="$BATS_TEST_TMPDIR/home"
	mkdir -p "$HOME"
	# CI の GITHUB_WORKSPACE 相当。共通基盤の最小複製を置く
	WS="$BATS_TEST_TMPDIR/ws"
	mkdir -p "$WS/scripts"
	cp "$REPO/scripts/new-service.sh" "$WS/scripts/"
	cp -a "$REPO/profiles" "$WS/profiles"
	cp -a "$REPO/common" "$WS/common"
	cp "$REPO/.ai-dev-foundation-root" "$WS/"
	PROJ="$WS/projects/svc"
	bash "$WS/scripts/new-service.sh" svc --profile product-static >/dev/null
}

# ---- 1. 側置きなら解決する ----

@test "緑: projects/<name> 配下から共通基盤のマーカーを解決できる" {
	# make -n はレシピを実行せず展開だけする。COMMON_ROOT が解決していれば
	# 共通側スクリプトの**絶対パス**が現れる
	run make -C "$PROJ" -n req-coverage
	[ "$status" -eq 0 ]
	[[ "$output" == *"$WS/common/scripts/check-requirements-coverage.sh"* ]]
}

@test "緑: tier-tripwire も共通側の実体を指す（複製を持たない）" {
	run make -C "$PROJ" -n tier-tripwire
	[ "$status" -eq 0 ]
	[[ "$output" == *"$WS/common/scripts/check-tier-tripwire.sh"* ]]
}

@test "緑: 検証対象のルートとしてプロジェクト側のパスが渡る（cwd に依存しない）" {
	run make -C "$PROJ" -n req-coverage
	[ "$status" -eq 0 ]
	[[ "$output" == *"$PROJ"* ]]
}

@test "緑: 深い階層から呼んでも解決する（CI が任意の作業ディレクトリで叩いても同じ）" {
	mkdir -p "$PROJ/src/deep/nested"
	run make -C "$PROJ/src/deep/nested" -f "$PROJ/Makefile" -n req-coverage
	[ "$status" -eq 0 ]
	[[ "$output" == *"$WS/common/scripts/check-requirements-coverage.sh"* ]]
}

# ---- 2. 側置きでなければ止まる ----

@test "赤: 共通基盤の外へ持ち出すと fail-closed で止まる（単独チェックアウト相当）" {
	# CI がプロジェクトだけを checkout した状態＝現在の CI で make が使えない理由
	ALONE="$BATS_TEST_TMPDIR/alone"
	mkdir -p "$ALONE"
	cp -a "$PROJ/." "$ALONE/"
	run make -C "$ALONE" -n req-coverage
	[ "$status" -ne 0 ]
	[[ "$output" == *"共通基盤のルート"* ]]
}

@test "赤: マーカーだけ消えても止まる（黙ってゲート無しで緑にしない）" {
	rm "$WS/.ai-dev-foundation-root"
	run make -C "$PROJ" -n req-coverage
	[ "$status" -ne 0 ]
	[[ "$output" == *".ai-dev-foundation-root"* ]]
}
