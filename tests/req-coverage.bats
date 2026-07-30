#!/usr/bin/env bats
# check-requirements-coverage.sh の負例回帰（恒久登録）。CI の bats で守る。
# フィクスチャは抽象トークンのみ（マーカーは REQMARK/ADVMARK、ID は R-1xx）。
# 固有ドメイン語・基盤の @req マーカー表記は使わない（基盤の tests/ スキャンを汚染しないため）。
# 2026-07-24 批准レス化（ADR-008）: 人間批准チェック（tests_ratified_by/sha）は廃止。
# 旧フィールドが無視されることを負例回帰として恒久登録する。

setup() {
	FIX="$BATS_TEST_TMPDIR/fix"
	mkdir -p "$FIX/scripts" "$FIX/docs/requirements" "$FIX/tests"
	cp "$BATS_TEST_DIRNAME/../common/scripts/check-requirements-coverage.sh" "$FIX/scripts/"
	SUT="$FIX/scripts/check-requirements-coverage.sh"
	: > "$FIX/.req-coverage-baseline"
}

rc() {
	REQ_TEST_PATHS=tests \
	REQ_MARKER_RE='REQMARK[[:space:]]+R-[0-9]+' \
	ADV_MARKER_RE='ADVMARK[[:space:]]+R-[0-9]+' \
	bash "$SUT" "$@"
}

@test "緑: S要件が被覆・adversarial有 → exit 0（批准フィールド不要）" {
	printf '%s\n' 'REQMARK R-100' 'ADVMARK R-100' 'body' > "$FIX/tests/t_100.txt"
	printf '%s\n' '---' 'id: R-100' 'tier: S' 'status: ratified' \
		'negative_space:' '  - "x"' '---' \
		> "$FIX/docs/requirements/R-100.md"
	run rc
	[ "$status" -eq 0 ]
}

@test "廃止回帰: 旧 tests_ratified_by/sha が残っていても無視される → exit 0（ADR-008）" {
	printf '%s\n' 'REQMARK R-100' 'ADVMARK R-100' 'body' > "$FIX/tests/t.txt"
	printf '%s\n' '---' 'id: R-100' 'tier: S' 'status: ratified' 'tests_ratified_by: h' \
		'tests_ratified_sha: deadbeef' 'negative_space:' '  - "x"' '---' \
		> "$FIX/docs/requirements/R-100.md"
	run rc
	[ "$status" -eq 0 ]
}

@test "B3: S/A要件をベースライン登録 → exit 2（設定エラー）" {
	printf '%s\n' '---' 'id: R-100' 'tier: S' 'status: ratified' '---' > "$FIX/docs/requirements/R-100.md"
	printf 'R-100\n' > "$FIX/.req-coverage-baseline"
	run rc
	[ "$status" -eq 2 ]
}

@test "dangling: 存在しない要件を指すマーカー → 赤(exit 1)" {
	printf '%s\n' 'REQMARK R-999' > "$FIX/tests/t.txt"
	run rc
	[ "$status" -eq 1 ]
}

@test "dangling: draft のままの要件を指すマーカー → 赤(exit 1)" {
	printf '%s\n' 'REQMARK R-100' > "$FIX/tests/t.txt"
	printf '%s\n' '---' 'id: R-100' 'tier: B' 'status: draft' '---' > "$FIX/docs/requirements/R-100.md"
	run rc
	[ "$status" -eq 1 ]
}

@test "S/A未カバー(マーカー0) → 赤(exit 1)" {
	printf '%s\n' '---' 'id: R-100' 'tier: S' 'status: ratified' '---' \
		> "$FIX/docs/requirements/R-100.md"
	run rc
	[ "$status" -eq 1 ]
}

@test "G4: negative_space有・adversarial無 → 赤(exit 1)" {
	printf '%s\n' 'REQMARK R-100' 'body' > "$FIX/tests/t.txt"
	printf '%s\n' '---' 'id: R-100' 'tier: S' 'status: ratified' \
		'negative_space:' '  - "x"' '---' \
		> "$FIX/docs/requirements/R-100.md"
	run rc
	[ "$status" -eq 1 ]
	[[ "$output" == *adversarial* ]]
}

@test "設定未定義(REQ_MARKER_RE無し) → exit 2（fail-closed）" {
	run env REQ_TEST_PATHS=tests bash "$SUT"
	[ "$status" -eq 2 ]
}

@test "配布テンプレ R-000-template.md は検証対象外 → exit 0（配線後も詰まらない）" {
	cp "$BATS_TEST_DIRNAME/../profiles/_base/docs/requirements/R-000-template.md" "$FIX/docs/requirements/"
	run rc
	[ "$status" -eq 0 ]
}

@test "fail-closed維持: テンプレでない実ファイルの不正tier(<S>) → exit 2" {
	printf '%s\n' '---' 'id: R-100' 'tier: <S>' 'status: ratified' '---' > "$FIX/docs/requirements/R-100.md"
	run rc
	[ "$status" -eq 2 ]
}

@test "fail-closed維持: テンプレでない実ファイルの不正tier(X) → exit 2" {
	printf '%s\n' '---' 'id: R-100' 'tier: X' 'status: ratified' '---' > "$FIX/docs/requirements/R-100.md"
	run rc
	[ "$status" -eq 2 ]
}

# ---- ROOT 引数（参照方式・2026-07-26 フェーズ0） ----

@test "ROOT引数: リポジトリ外のスクリプトから対象リポを指定して検証できる" {
	EXT="$BATS_TEST_DIRNAME/../common/scripts/check-requirements-coverage.sh"
	run env REQ_TEST_PATHS=tests REQ_MARKER_RE='REQMARK[[:space:]]+R-[0-9]+' ADV_MARKER_RE='ADVMARK[[:space:]]+R-[0-9]+' \
		bash "$EXT" "$FIX"
	[ "$status" -eq 0 ]
}

@test "ROOT引数: 存在しないルートを渡すと exit 2（fail-closed）" {
	EXT="$BATS_TEST_DIRNAME/../common/scripts/check-requirements-coverage.sh"
	run env REQ_TEST_PATHS=tests bash "$EXT" "$BATS_TEST_TMPDIR/nope"
	[ "$status" -eq 2 ]
}
