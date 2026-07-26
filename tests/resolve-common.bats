#!/usr/bin/env bats
# 参照方式の全解決の起点であるマーカー探索（common/scripts/resolve-common.sh）と、
# その上に載る番人フック（service-templates/claude/scripts/guard-shim.sh）の固定資産テスト。
#
# なぜテストで固定するか: この2つが黙って失敗すると「共通ルールが読まれていないのに緑」
# 「ガードが動いていないのに緑」という、この基盤が繰り返し潰してきた失敗類型がそのまま戻る。
# 見つからないときに**止まる**ことこそが仕様であり、そこを回帰テストで固定する。
#
# @req: R-001
# @adversarial: R-001

RESOLVE="${BATS_TEST_DIRNAME}/../common/scripts/resolve-common.sh"
SHIM="${BATS_TEST_DIRNAME}/../service-templates/claude/scripts/guard-shim.sh"

setup() {
	W="$BATS_TEST_TMPDIR/w"
	mkdir -p "$W/foundation/projects/svc/deep/nested"
	touch "$W/foundation/.ai-dev-foundation-root"
	mkdir -p "$W/orphan/projects/svc"
}

# ---- マーカー探索 ----

@test "resolve: マーカーと同じディレクトリから解決できる" {
	run bash -c 'source "$1"; cd "$2"; resolve_common_root' _ "$RESOLVE" "$W/foundation"
	[ "$status" -eq 0 ]
	[ "$output" = "$W/foundation" ]
}

@test "resolve: 1つ下の階層から遡って解決できる" {
	run bash -c 'source "$1"; cd "$2"; resolve_common_root' _ "$RESOLVE" "$W/foundation/projects/svc"
	[ "$status" -eq 0 ]
	[ "$output" = "$W/foundation" ]
}

@test "resolve: 深い階層からでも解決できる（深さを仮定しない）" {
	run bash -c 'source "$1"; cd "$2"; resolve_common_root' _ "$RESOLVE" "$W/foundation/projects/svc/deep/nested"
	[ "$status" -eq 0 ]
	[ "$output" = "$W/foundation" ]
}

@test "resolve: 起点を引数で明示できる（cwd に依存しない）" {
	run bash -c 'source "$1"; cd /; resolve_common_root "$2"' _ "$RESOLVE" "$W/foundation/projects/svc"
	[ "$status" -eq 0 ]
	[ "$output" = "$W/foundation" ]
}

@test "resolve: マーカーが無ければ非ゼロで終了する（fail-closed）" {
	run bash -c 'source "$1"; cd "$2"; resolve_common_root' _ "$RESOLVE" "$W/orphan/projects/svc"
	[ "$status" -ne 0 ]
	[[ "$output" == *"見つかりません"* ]]
}

@test "resolve: 起点ディレクトリが存在しなければ exit 2" {
	run bash -c 'source "$1"; resolve_common_root "$2"' _ "$RESOLVE" "$W/does-not-exist"
	[ "$status" -eq 2 ]
}

# ---- 番人フック ----

@test "shim: マーカーが無ければ exit 2 で Bash をブロックする（fail-open にしない）" {
	cd "$W/orphan/projects/svc"
	run bash "$SHIM"
	[ "$status" -eq 2 ]
	[[ "$output" == *"ブロック"* ]]
}

@test "shim: マーカーがあれば共通側のガードへ委譲する" {
	mkdir -p "$W/foundation/.claude/scripts"
	printf '#!/usr/bin/env bash\necho DELEGATED_OK\nexit 0\n' > "$W/foundation/.claude/scripts/guard-dangerous.sh"
	chmod +x "$W/foundation/.claude/scripts/guard-dangerous.sh"
	cd "$W/foundation/projects/svc/deep/nested"
	run bash "$SHIM"
	[ "$status" -eq 0 ]
	[ "$output" = "DELEGATED_OK" ]
}

@test "shim: 委譲先に標準入力（フックJSON）が渡る" {
	mkdir -p "$W/foundation/.claude/scripts"
	printf '#!/usr/bin/env bash\ncat\n' > "$W/foundation/.claude/scripts/guard-dangerous.sh"
	chmod +x "$W/foundation/.claude/scripts/guard-dangerous.sh"
	cd "$W/foundation/projects/svc"
	run bash -c 'printf "HOOK_JSON_PASSED" | bash "$1"' _ "$SHIM"
	[ "$status" -eq 0 ]
	[ "$output" = "HOOK_JSON_PASSED" ]
}
