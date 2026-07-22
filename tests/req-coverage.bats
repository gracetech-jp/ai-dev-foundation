#!/usr/bin/env bats
# check-requirements-coverage.sh の負例回帰（恒久登録）。CI の bats で守る。
# フィクスチャは抽象トークンのみ（マーカーは REQMARK/ADVMARK、ID は R-1xx）。
# 固有ドメイン語・基盤の @req マーカー表記は使わない（基盤の tests/ スキャンを汚染しないため）。

setup() {
	FIX="$BATS_TEST_TMPDIR/fix"
	mkdir -p "$FIX/scripts" "$FIX/docs/requirements" "$FIX/tests"
	cp "$BATS_TEST_DIRNAME/../scripts/check-requirements-coverage.sh" "$FIX/scripts/"
	SUT="$FIX/scripts/check-requirements-coverage.sh"
	: > "$FIX/.req-coverage-baseline"
}

rc() {
	REQ_TEST_PATHS=tests \
	REQ_MARKER_RE='REQMARK[[:space:]]+R-[0-9]+' \
	ADV_MARKER_RE='ADVMARK[[:space:]]+R-[0-9]+' \
	REQ_COMMENT_PREFIX='#' \
	bash "$SUT" "$@"
}

@test "緑: S要件が被覆・妥当性批准・sha一致・adversarial有 → exit 0" {
	printf '%s\n' 'REQMARK R-100' 'ADVMARK R-100' 'body' > "$FIX/tests/t_100.txt"
	printf '%s\n' '---' 'id: R-100' 'tier: S' 'status: ratified' 'ratified_by: h' \
		'tests_ratified_by: h' 'tests_ratified_sha: PENDING' \
		'test_assets:' '  - "tests/t_100.txt"' 'negative_space:' '  - "x"' '---' \
		> "$FIX/docs/requirements/R-100.md"
	sha="$(rc --sha R-100)"
	sed -i "s/PENDING/$sha/" "$FIX/docs/requirements/R-100.md"
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

@test "F1: 批准後にテスト改変(sha不一致) → 赤(exit 1)" {
	printf '%s\n' 'REQMARK R-100' 'ADVMARK R-100' 'body' > "$FIX/tests/t.txt"
	printf '%s\n' '---' 'id: R-100' 'tier: S' 'status: ratified' 'tests_ratified_by: h' \
		'tests_ratified_sha: deadbeef' 'test_assets:' '  - "tests/t.txt"' 'negative_space:' '  - "x"' '---' \
		> "$FIX/docs/requirements/R-100.md"
	run rc
	[ "$status" -eq 1 ]
	[[ "$output" == *F1* ]]
}

@test "S/A未カバー(マーカー0) → 赤(exit 1)" {
	printf '%s\n' '---' 'id: R-100' 'tier: S' 'status: ratified' 'tests_ratified_by: h' 'tests_ratified_sha: x' '---' \
		> "$FIX/docs/requirements/R-100.md"
	run rc
	[ "$status" -eq 1 ]
}

@test "G4: negative_space有・adversarial無 → 赤(exit 1)" {
	printf '%s\n' 'REQMARK R-100' 'body' > "$FIX/tests/t.txt"
	printf '%s\n' '---' 'id: R-100' 'tier: S' 'status: ratified' 'tests_ratified_by: h' \
		'tests_ratified_sha: PENDING' 'test_assets:' '  - "tests/t.txt"' 'negative_space:' '  - "x"' '---' \
		> "$FIX/docs/requirements/R-100.md"
	sha="$(rc --sha R-100)"
	sed -i "s/PENDING/$sha/" "$FIX/docs/requirements/R-100.md"
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
