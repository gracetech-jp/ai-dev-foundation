#!/usr/bin/env bats
# check-tier-tripwire.sh の負例回帰（恒久登録）。CI の bats で守る。
# フィクスチャは抽象トークンのみ（機微パス src/sensitive/**、機微シンボル SECRETSYM）。
# 固有ドメイン語（RLS/tenant/課金等）は使わない。

setup() {
	FIX="$BATS_TEST_TMPDIR/fix"
	mkdir -p "$FIX/scripts" "$FIX/docs/requirements" "$FIX/src/sensitive" "$FIX/src/util" "$FIX/tests"
	cp "$BATS_TEST_DIRNAME/../common/scripts/check-tier-tripwire.sh" "$FIX/scripts/"
	SUT="$FIX/scripts/check-tier-tripwire.sh"
	printf 'base\n' > "$FIX/src/sensitive/a.txt"
	printf 'base\n' > "$FIX/src/util/b.txt"
	( cd "$FIX" && git init -q -b main && git config user.email t@t && git config user.name t && git add -A && git commit -qm base )
	BASE="$( cd "$FIX" && git rev-parse HEAD )"
}

# 変更をコミットし、機微設定でトリップワイヤを実行する
commit() { ( cd "$FIX" && git add -A && git commit -qm chg ); }
tw() { TIER_TRIPWIRE_PATHS='src/sensitive/**' TIER_TRIPWIRE_SYMBOLS='SECRETSYM' TRIPWIRE_BASE="$BASE" bash "$SUT"; }
mkreq() { # <id> <tier> <status> <pathglob>
	printf '%s\n' '---' "id: $1" "tier: $2" "status: $3" 'paths:' "  - \"$4\"" '---' > "$FIX/docs/requirements/$1.md"
}

@test "M1: 未定義(env無し) → exit 2" {
	run bash "$SUT"
	[ "$status" -eq 2 ]
}

@test "M1: 空設定・.tier-tripwire-none 無し → exit 2" {
	run env TIER_TRIPWIRE_PATHS='' TIER_TRIPWIRE_SYMBOLS='' bash "$SUT"
	[ "$status" -eq 2 ]
}

@test "M1: 空設定・.tier-tripwire-none 有り → skip 0" {
	: > "$FIX/docs/requirements/.tier-tripwire-none"
	run env TIER_TRIPWIRE_PATHS='' TIER_TRIPWIRE_SYMBOLS='' bash "$SUT"
	[ "$status" -eq 0 ]
}

@test "F2: 機微シンボルを非機微パスに混入・S要件なし → 赤(1)" {
	printf 'x SECRETSYM y\n' > "$FIX/src/util/b.txt"; commit
	run tw
	[ "$status" -eq 1 ]
}

@test "F2: 機微シンボル・S要件が正しく統べる → 緑(0)" {
	mkreq R-100 S ratified 'src/util/**'
	printf 'x SECRETSYM y\n' > "$FIX/src/util/b.txt"; commit
	run tw
	[ "$status" -eq 0 ]
}

@test "F2削除: 機微シンボル行の削除 → トリップ赤(1)" {
	printf 'has SECRETSYM here\n' > "$FIX/src/util/b.txt"; commit
	local base2; base2="$( cd "$FIX" && git rev-parse HEAD )"
	printf 'removed\n' > "$FIX/src/util/b.txt"; commit
	run env TIER_TRIPWIRE_PATHS='src/sensitive/**' TIER_TRIPWIRE_SYMBOLS='SECRETSYM' TRIPWIRE_BASE="$base2" bash "$SUT"
	[ "$status" -eq 1 ]
}

@test "デスカレーション: 機微変更を tier<S 要件が統べる → 赤(1)" {
	mkreq R-200 B ratified 'src/sensitive/**'
	printf 'changed\n' > "$FIX/src/sensitive/a.txt"; commit
	run tw
	[ "$status" -eq 1 ]
}

@test "F3: 機微 test/fixture・統べるS要件なし → 赤(1)" {
	printf 'x SECRETSYM y\n' > "$FIX/tests/t_x.txt"; commit
	run tw
	[ "$status" -eq 1 ]
}

@test "F3: 機微 test/fixture・S要件が統べる → 緑(0)" {
	mkreq R-100 S ratified 'tests/**'
	printf 'x SECRETSYM y\n' > "$FIX/tests/t_x.txt"; commit
	run tw
	[ "$status" -eq 0 ]
}

@test "allowlist: 違反を .tier-tripwire-allow に登録 → 緑(0・警告へ緩和)" {
	printf 'src/util/b.txt\n' > "$FIX/.tier-tripwire-allow"
	printf 'x SECRETSYM y\n' > "$FIX/src/util/b.txt"; commit
	run tw
	[ "$status" -eq 0 ]
	[[ "$output" == *allow* ]]
}

@test "無要件: 機微パスを要件なしで変更 → 赤(1)" {
	printf 'changed\n' > "$FIX/src/sensitive/a.txt"; commit
	run tw
	[ "$status" -eq 1 ]
}

@test "SELF_RE: 機微パターンの定義元ファイルは軽微扱いで緑（永久赤の回避）" {
	printf 'TIER_TRIPWIRE_SYMBOLS=SECRETSYM\n' > "$FIX/Makefile"; commit
	run env TIER_TRIPWIRE_PATHS='src/sensitive/**' TIER_TRIPWIRE_SYMBOLS='SECRETSYM' \
		TIER_TRIPWIRE_SELF_RE='^Makefile$' TRIPWIRE_BASE="$BASE" bash "$SUT"
	[ "$status" -eq 0 ]
	[[ "$output" == *"定義元ファイルに一致"* ]]
}

@test "SELF_RE: 未設定なら定義元も除外されない（fail-closed 維持）" {
	printf 'TIER_TRIPWIRE_SYMBOLS=SECRETSYM\n' > "$FIX/Makefile"; commit
	run tw
	[ "$status" -eq 1 ]
}

@test "SELF_RE: 除外は定義元だけで、機微コード本体は従来どおり赤" {
	printf 'TIER_TRIPWIRE_SYMBOLS=SECRETSYM\n' > "$FIX/Makefile"
	printf 'x SECRETSYM y\n' > "$FIX/src/util/b.txt"; commit
	run env TIER_TRIPWIRE_PATHS='src/sensitive/**' TIER_TRIPWIRE_SYMBOLS='SECRETSYM' \
		TIER_TRIPWIRE_SELF_RE='^Makefile$' TRIPWIRE_BASE="$BASE" bash "$SUT"
	[ "$status" -eq 1 ]
}

# ---- ROOT 引数（参照方式・2026-07-26 フェーズ0） ----
# 共通リポの common/scripts/ に置いたスクリプトから、別ディレクトリのリポジトリを検証できること。
# 位置からの導出（BASH_SOURCE）だけだと、スクリプトと検証対象が別リポになった瞬間に破綻する。

@test "ROOT引数: リポジトリ外のスクリプトから対象リポを指定して検証できる" {
	EXT="$BATS_TEST_DIRNAME/../common/scripts/check-tier-tripwire.sh"
	printf 'x\n' >> "$FIX/src/util/b.txt"
	commit
	run env TIER_TRIPWIRE_PATHS='src/sensitive/**' TIER_TRIPWIRE_SYMBOLS='SECRETSYM' TRIPWIRE_BASE="$BASE" \
		bash "$EXT" "$FIX"
	[ "$status" -eq 0 ]
	[[ "$output" == *"機微パス/シンボルに触れる変更はありません"* ]]
}

@test "ROOT引数: 存在しないルートを渡すと exit 2（fail-closed）" {
	EXT="$BATS_TEST_DIRNAME/../common/scripts/check-tier-tripwire.sh"
	run env TIER_TRIPWIRE_PATHS='src/sensitive/**' bash "$EXT" "$BATS_TEST_TMPDIR/nope"
	[ "$status" -eq 2 ]
}
