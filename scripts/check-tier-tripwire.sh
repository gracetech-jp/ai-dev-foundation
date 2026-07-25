#!/usr/bin/env bash
# check-tier-tripwire.sh — Tier の自己申告デスカレーションをコード実態から裏取りするゲート。
# 機微コード（パス∪シンボル）への変更に、統べる ratified Tier-S 要件が無い/ tier<S なら赤にする。
# 設計の正: docs/rules/tiers.md（Tier付与の裏取り）/ docs/rules/requirements.md（要件↔paths）。
# 既存作法踏襲: set -u・fail-closed・既定値を持たない（機微の定義は各サービスが SERVICE.md で行う）。
#
# 終了コード: 0=OK（または正当スキップ）/ 1=デスカレーション検出（赤）/ 2=設定エラー（fail-closed）。
#
# 設定（機微パターンはサービス固有のため SERVICE.md 由来。Makefile の tier-tripwire が export する）:
#   TIER_TRIPWIRE_PATHS   … 機微コードのパス glob（| 区切り）。共通リポは既定値を持たない。
#   TIER_TRIPWIRE_SYMBOLS … パス名に現れない機微識別子の拡張正規表現（| で alternation 可）。
#   TIER_TRIPWIRE_TEST_RE … test/fixture 判定の正規表現（任意。既定はスタック中立の一般形）。
#   TIER_TRIPWIRE_SELF_RE … 機微パターンの定義元ファイル（Makefile 等）の除外正規表現（任意・既定は空）。
#   TRIPWIRE_BASE         … 差分の基準（任意。既定は origin/main → HEAD~1 → 空ツリーの順で自動選択）。

set -u
shopt -s nullglob

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 2
REQ_DIR="docs/requirements"
ALLOW=".tier-tripwire-allow"
NONE_ACK="docs/requirements/.tier-tripwire-none"

fail=0
hit()  { echo "  ❌ $1" >&2; fail=1; }
warn() { echo "  ⚠ $1" >&2; }
die()  { echo "❌ $1" >&2; exit 2; }

command -v git >/dev/null 2>&1 || die "git が見つかりません（fail-closed）"

# ---- M1: 既定値ゼロ＋未定義fail-closed ----
# `-`（`:-`ではない）で「一度も設定されていない(__UNSET__)」と「明示的に空」を区別する。
SENS_PATHS="${TIER_TRIPWIRE_PATHS-__UNSET__}"
SENS_SYMS="${TIER_TRIPWIRE_SYMBOLS-__UNSET__}"
p_unset=0; s_unset=0
[ "$SENS_PATHS" = "__UNSET__" ] && { p_unset=1; SENS_PATHS=""; }
[ "$SENS_SYMS" = "__UNSET__" ]  && { s_unset=1; SENS_SYMS=""; }

if [ "$p_unset" -eq 1 ] && [ "$s_unset" -eq 1 ]; then
	die "TIER_TRIPWIRE_PATHS / TIER_TRIPWIRE_SYMBOLS 未定義。SERVICE.md で機微パターンを定義するか、機微面が無いなら $NONE_ACK をコミットして明示宣言してください（緑にしない＝fail-closed）"
fi
if [ -z "$SENS_PATHS" ] && [ -z "$SENS_SYMS" ]; then
	# 明示的に空 → 「機微面なし」の明示宣言を要求
	if [ -f "$NONE_ACK" ]; then
		echo "[tier-tripwire] 機微面なし（$NONE_ACK 宣言済み）: skip"
		exit 0
	fi
	die "機微パターンが空です。空設定には $NONE_ACK のコミットで「機微面なし」を明示宣言してください（fail-closed）"
fi

TEST_RE="${TIER_TRIPWIRE_TEST_RE:-(^|/)(tests?|fixtures?)/|(^|/)test_|_test\.|\.test\.}"

# 機微パターンの定義元ファイル（自己言及の除外）。TIER_TRIPWIRE_SYMBOLS の値そのものを書いている
# ファイル（Makefile 等）は、grep すれば当然パターンに一致するが機微コードではない。除外しないと
# 定義元を触るたびに永久に赤になる。未設定なら何も除外しない（fail-closed 維持）。
# *.md は is_docs が既に軽微扱いのため、通常ここに書くのは Makefile 等の非 docs だけでよい。
# （2026-07-25 sumai-desk から基盤へ取り込み。ADR-009 以降、共通所有ファイルの改善は基盤で行う）
SELF_RE="${TIER_TRIPWIRE_SELF_RE:-}"

# ---- front-matter パーサ（check-requirements-coverage.sh と同仕様） ----
fm_scalar() { # <file> <key>
	awk -v key="$2" '
		NR==1 && $0=="---" { inb=1; next }
		inb && $0=="---"   { exit }
		inb && $0 ~ "^"key":[[:space:]]*" {
			sub("^"key":[[:space:]]*", "", $0); gsub(/^"|"$/, "", $0); print $0; exit
		}' "$1"
}
fm_list() { # <file> <key>
	awk -v key="$2" '
		NR==1 && $0=="---" { inb=1; next }
		inb && $0=="---"   { exit }
		inb {
			if ($0 ~ "^"key":[[:space:]]*$") { inl=1; next }
			if (inl) {
				if ($0 ~ /^[[:space:]]*-[[:space:]]+/) { line=$0; sub(/^[[:space:]]*-[[:space:]]+/,"",line); gsub(/^"|"$/,"",line); print line; next }
				else if ($0 ~ /^[^[:space:]#]/) { inl=0 }
			}
		}' "$1"
}

# パス glob 一致（| 区切り。RHS は意図的な glob）
path_match() { # <file>
	local f="$1" g IFS='|'
	for g in $SENS_PATHS; do
		[ -n "$g" ] || continue
		# shellcheck disable=SC2053
		[[ "$f" == $g ]] && return 0
	done
	return 1
}
is_docs() { case "$1" in *.md) return 0 ;; docs/*|*/docs/*) return 0 ;; *) return 1 ;; esac; }
is_test() { printf '%s' "$1" | grep -qE "$TEST_RE"; }
is_self() { [ -n "$SELF_RE" ] && printf '%s' "$1" | grep -qE "$SELF_RE"; }

# 統べる要件の探索：needs_s=1 なら ratified かつ tier==S、needs_s=0 なら ratified 全 tier。
owning_req() { # <file> <needs_s>
	local file="$1" needs="$2" rf status tier id g
	for rf in "$REQ_DIR"/R-*.md; do
		status="$(fm_scalar "$rf" status)"; [ "$status" = "ratified" ] || continue
		tier="$(fm_scalar "$rf" tier)"
		[ "$needs" -eq 1 ] && [ "$tier" != "S" ] && continue
		id="$(fm_scalar "$rf" id)"
		while IFS= read -r g; do
			[ -n "$g" ] || continue
			# shellcheck disable=SC2053
			if [[ "$file" == $g ]]; then printf '%s' "$id"; return 0; fi
		done < <(fm_list "$rf" paths)
	done
	return 1
}

# 明示登録の例外 allowlist（赤→警告に緩和）
allow_match() { # <file>
	[ -f "$ALLOW" ] || return 1
	local pat
	while IFS= read -r pat; do
		pat="${pat%%#*}"; pat="$(printf '%s' "$pat" | tr -d '[:space:]')"
		[ -n "$pat" ] || continue
		# shellcheck disable=SC2053
		[[ "$1" == $pat ]] && return 0
	done < "$ALLOW"
	return 1
}
tripwire_hit() { # <file> <message>：allowlist にあれば警告へ緩和、無ければ赤
	if allow_match "$1"; then
		warn "[allow] $2（$ALLOW で緩和・明示登録済み）"
	else
		hit "$2"
	fi
}

# ---- 差分の基準を決める ----
EMPTY_TREE="$(git hash-object -t tree /dev/null 2>/dev/null || echo 4b825dc642cb6eb9a060e54bf8d69288fbee4904)"
BASE="${TRIPWIRE_BASE:-}"
if [ -z "$BASE" ]; then
	if   git rev-parse --verify -q origin/main >/dev/null 2>&1; then BASE="origin/main"
	elif git rev-parse --verify -q "HEAD~1"    >/dev/null 2>&1; then BASE="HEAD~1"
	else BASE="$EMPTY_TREE"; fi
fi
diff_names()      { if [ "$BASE" = "$EMPTY_TREE" ]; then git diff --name-only "$BASE" HEAD; else git diff --name-only "$BASE...HEAD"; fi; }
diff_hunks_file() { if [ "$BASE" = "$EMPTY_TREE" ]; then git diff --unified=0 "$BASE" HEAD -- "$1"; else git diff --unified=0 "$BASE...HEAD" -- "$1"; fi; }
echo "[tier-tripwire] 差分基準: $BASE"

# ---- F2: パス ∪ シンボル の和集合 ----
changed="$(diff_names 2>/dev/null || true)"
path_hits=""
sym_hits=""
while IFS= read -r f; do
	[ -n "$f" ] || continue
	# ① パス一致
	path_match "$f" && path_hits+="$f"$'\n'
	# ② シンボル一致（追加行 ^+ と削除行 ^- の双方。ヘッダ行は除外）。弱体化は削除で起きるため削除も対象。
	if [ -n "$SENS_SYMS" ]; then
		if diff_hunks_file "$f" | grep -E '^[+-]' | grep -vE '^(\+\+\+|---) ' | sed 's/^[+-]//' | grep -qE "$SENS_SYMS"; then
			sym_hits+="$f"$'\n'
		fi
	fi
done <<< "$changed"

sens="$(printf '%s%s' "$path_hits" "$sym_hits" | sed '/^$/d' | sort -u)"

# ---- 機微変更の振り分け ----
if [ -n "$sens" ]; then
	while IFS= read -r f; do
		[ -n "$f" ] || continue
		if is_docs "$f"; then
			warn "機微パターンが docs に一致: $f（軽微）"
			continue
		fi
		if is_self "$f"; then
			warn "機微パターンが定義元ファイルに一致: $f（軽微。TIER_TRIPWIRE_SELF_RE で除外）"
			continue
		fi
		if is_test "$f"; then
			# test/fixture は警告に落とさない。統べる ratified Tier-S 要件を要求する。
			local_s="$(owning_req "$f" 1 || true)"
			if [ -z "$local_s" ]; then
				tripwire_hit "$f" "機微 test/fixture $f を統べる ratified Tier-S 要件が無い"
			else
				echo "  ℹ 機微 test/fixture $f は $local_s が統べる"
			fi
			continue
		fi
		# プロダクトコード
		s_owner="$(owning_req "$f" 1 || true)"
		if [ -n "$s_owner" ]; then
			echo "  ℹ 機微変更 $f は Tier-S 要件 $s_owner が統べる"
		else
			any_owner="$(owning_req "$f" 0 || true)"
			if [ -n "$any_owner" ]; then
				tripwire_hit "$f" "申告デスカレーション: $f を統べる要件 $any_owner が tier<S（Tier-S 要件が必要）"
			else
				tripwire_hit "$f" "無要件/デスカレーション: 機微変更 $f を統べる ratified Tier-S 要件が無い"
			fi
		fi
	done <<< "$sens"
else
	echo "[tier-tripwire] 機微パス/シンボルに触れる変更はありません。"
fi

# ---- S4: グリーンフィールドの空虚な緑（PR非依存の静的走査。警告のみ） ----
# 差分ベースの検査は「最初から機微コードがあって要件が1件も無い」状態を素通りするため、
# 変更の有無と無関係に静的走査で網を張る（人間批准とは無関係の機械ゲート。ADR-008 §維持したもの）。
s_req_count=0
for rf in "$REQ_DIR"/R-*.md; do
	[ "$(fm_scalar "$rf" status)" = "ratified" ] && [ "$(fm_scalar "$rf" tier)" = "S" ] && s_req_count=$(( s_req_count + 1 ))
done
if [ "$s_req_count" -eq 0 ]; then
	static_hit=0
	if [ -n "$SENS_PATHS" ]; then
		while IFS= read -r tracked; do
			path_match "$tracked" && { static_hit=1; break; }
		done < <(git ls-files)
	fi
	if [ "$static_hit" -eq 0 ] && [ -n "$SENS_SYMS" ]; then
		git grep -lE "$SENS_SYMS" -- ':!docs' >/dev/null 2>&1 && static_hit=1
	fi
	[ "$static_hit" -eq 1 ] && warn "機微パス/シンボルが存在するが ratified Tier-S 要件が0件（空虚な緑の疑い。S4）"
fi

if [ "$fail" -ne 0 ]; then
	echo "[tier-tripwire] ❌ Tier デスカレーション/無要件の機微変更を検出しました。" >&2
	exit 1
fi
echo "[tier-tripwire] ✅ 機微変更は適切な Tier-S 要件に統べられています。"
exit 0
