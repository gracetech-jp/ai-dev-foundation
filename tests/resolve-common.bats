#!/usr/bin/env bats
# 参照方式の全解決の起点であるマーカー探索（common/scripts/resolve-common.sh）の固定資産テスト。
#
# なぜテストで固定するか: これが黙って失敗すると「共通ルールが読まれていないのに緑」という、
# この基盤が繰り返し潰してきた失敗類型がそのまま戻る。
# 見つからないときに**止まる**ことこそが仕様であり、そこを回帰テストで固定する。
#
# 番人フック（guard-shim.sh）の6ケースは 2026-08-04 に削除した（ADR-012 決定3でシムを廃止）。
# シムが塞いでいた fail-open は、共通 .claude をユーザースコープへマウントし絶対パスのフックを
# 1本だけ持つ構成（ADR-013 のマウント設計）で構造的に解けている。
#
# @req: R-001
# @adversarial: R-001

RESOLVE="${BATS_TEST_DIRNAME}/../common/scripts/resolve-common.sh"

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
