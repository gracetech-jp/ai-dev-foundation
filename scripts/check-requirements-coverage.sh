#!/usr/bin/env bash
# check-requirements-coverage.sh — 批准済み要件↔テストの紐づけ・妥当性・改変を機械検証する。
# 設計の正: docs/rules/requirements.md（特に §7 tests_ratified_sha 仕様）/ docs/rules/tiers.md /
#           docs/rules/quality-gates.md §5（一方向ラチェット思想）。
# 既存作法踏襲: set -u・fail-closed・自己申告を信頼しない（人間批准とコード実態で裏取り）。
#
# 終了コード: 0=OK / 1=要件未達（赤）/ 2=設定エラー・破損（fail-closed）。
#
# 設定（マーカー文字列はスタック依存のため SERVICE.md 由来。Makefile の req-coverage が export する）:
#   REQ_TEST_PATHS     … テストを探索するパス（空白区切り）。必須（未設定は exit 2）。
#   REQ_MARKER_RE      … req マーカー行にマッチする拡張正規表現（R-<数字> を含むこと）。必須（未設定は exit 2）。
#   ADV_MARKER_RE      … adversarial マーカー行の拡張正規表現。未設定なら adversarial 被覆なし扱い。
#   REQ_COMMENT_PREFIX … §7④ の行頭コメント記法（例 '#'）。未設定なら ④ をスキップ（①②③のみ）。
#
# 使い方:
#   bash scripts/check-requirements-coverage.sh            # 全要件を検証
#   bash scripts/check-requirements-coverage.sh --sha R-001  # 指定要件の現在ハッシュのみ算出して出力（批准時の検算用）

set -u
shopt -s nullglob

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 2
REQ_DIR="docs/requirements"
BASELINE=".req-coverage-baseline"

fail=0
report() { echo "  ❌ $1" >&2; fail=1; }
die()    { echo "❌ $1" >&2; exit 2; }

command -v sha256sum >/dev/null 2>&1 || die "sha256sum が見つかりません（fail-closed）"

REQ_TEST_PATHS="${REQ_TEST_PATHS:-}"
REQ_MARKER_RE="${REQ_MARKER_RE:-}"
ADV_MARKER_RE="${ADV_MARKER_RE:-}"
REQ_COMMENT_PREFIX="${REQ_COMMENT_PREFIX:-}"

[ -n "$REQ_MARKER_RE" ]  || die "REQ_MARKER_RE 未設定（SERVICE.md 由来のマーカー正規表現。fail-closed）"
[ -n "$REQ_TEST_PATHS" ] || die "REQ_TEST_PATHS 未設定（テスト探索パス。fail-closed）"
[ -d "$REQ_DIR" ]        || die "$REQ_DIR がありません（要件ディレクトリ。fail-closed）"

# ---- front-matter パーサ（先頭の --- ... --- ブロックのみ対象） ----
fm_scalar() { # <file> <key>
	awk -v key="$2" '
		NR==1 && $0=="---" { inb=1; next }
		inb && $0=="---"   { exit }
		inb && $0 ~ "^"key":[[:space:]]*" {
			sub("^"key":[[:space:]]*", "", $0)
			gsub(/^"|"$/, "", $0)
			print $0; exit
		}' "$1"
}
fm_list() { # <file> <key> -> 各要素を1行ずつ
	awk -v key="$2" '
		NR==1 && $0=="---" { inb=1; next }
		inb && $0=="---"   { exit }
		inb {
			if ($0 ~ "^"key":[[:space:]]*$") { inl=1; next }
			if (inl) {
				if ($0 ~ /^[[:space:]]*-[[:space:]]+/) {
					line=$0
					sub(/^[[:space:]]*-[[:space:]]+/, "", line)
					gsub(/^"|"$/, "", line)
					print line; next
				} else if ($0 ~ /^[^[:space:]#]/) { inl=0 }
			}
		}' "$1"
}

# ---- 要件収集＋front-matterバリデーション（破損は fail-closed） ----
declare -A R_TIER R_STATUS R_TR R_SHA R_NEG R_FILE
reqs=()
for f in "$REQ_DIR"/R-*.md; do
	id="$(fm_scalar "$f" id)"
	tier="$(fm_scalar "$f" tier)"
	status="$(fm_scalar "$f" status)"
	printf '%s' "$id" | grep -qE '^R-[0-9]+$' || die "front-matter id が R-<数字> でない: $f （'$id'）"
	case "$tier" in S|A|B|C) ;; *) die "front-matter tier が S|A|B|C でない: $f （'$tier'）" ;; esac
	[ -z "${R_TIER[$id]:-}" ] || die "要件ID重複: $id（$f と ${R_FILE[$id]}）"
	reqs+=("$id")
	R_TIER[$id]="$tier"; R_STATUS[$id]="$status"
	R_TR[$id]="$(fm_scalar "$f" tests_ratified_by)"
	R_SHA[$id]="$(fm_scalar "$f" tests_ratified_sha)"
	R_FILE[$id]="$f"
	if [ -n "$(fm_list "$f" negative_space | head -n1)" ]; then R_NEG[$id]=1; else R_NEG[$id]=0; fi
	# test_assets の事前検証（主シェルで実施＝die が全体を止める）:
	#   修正2(b) 空白パスは fail-closed / 修正3 0件マッチ glob は警告（紐づけ漏れの surface。赤にはしない）
	while IFS= read -r g; do
		[ -n "$g" ] || continue
		matched=0
		while IFS= read -r m; do
			[ -e "$m" ] || continue
			case "$m" in *[[:space:]]*) die "test_assets の対象パスに空白が含まれます: '$m'（要件 $id。決定論のため空白禁止。docs/rules/requirements.md §7）" ;; esac
			matched=$(( matched + 1 ))
		done < <(compgen -G "$g" || true)
		[ "$matched" -gt 0 ] || echo "  ⚠ test_assets glob が0件マッチ: '$g'（要件 $id。fixture 紐づけ漏れの疑い。docs/rules/requirements.md §8）" >&2
	done < <(fm_list "$f" test_assets)
done

# ---- テスト走査：マーカー→被覆／adversarial被覆／要件別の保持ファイル集合 ----
declare -A COVER ADV MARK_FILES
read -r -a _paths <<< "$REQ_TEST_PATHS"
test_files=()
for p in "${_paths[@]}"; do
	[ -e "$p" ] || continue
	while IFS= read -r tf; do
		# 修正2(b): 空白を含む対象パスは決定論を壊すため fail-closed（主シェルなので die が全体を止める）
		case "$tf" in *[[:space:]]*) die "テスト対象パスに空白が含まれます: '$tf'（決定論のため空白禁止。docs/rules/requirements.md §7）" ;; esac
		test_files+=("$tf")
	done < <(find "$p" -type f | sort)
done
for tf in "${test_files[@]}"; do
	while IFS= read -r rid; do
		COVER[$rid]=$(( ${COVER[$rid]:-0} + 1 ))
		MARK_FILES[$rid]="${MARK_FILES[$rid]:-} $tf"
	done < <(grep -oE "$REQ_MARKER_RE" "$tf" 2>/dev/null | grep -oE 'R-[0-9]+' | sort -u)
	if [ -n "$ADV_MARKER_RE" ]; then
		while IFS= read -r aid; do
			ADV[$aid]=1
			MARK_FILES[$aid]="${MARK_FILES[$aid]:-} $tf"
		done < <(grep -oE "$ADV_MARKER_RE" "$tf" 2>/dev/null | grep -oE 'R-[0-9]+' | sort -u)
	fi
done

# ---- §7 準拠のハッシュ算出（ファイル単位・パス昇順連結・関数抽出なし・フォールバック分岐なし） ----
normalize_file() { # <file>: ①CRLF→LF ②行末空白除去 ③空行除去 ④行頭コメント行除去(prefix定義時のみ)
	local out
	out="$(sed -e 's/\r$//' -e 's/[[:space:]]*$//' "$1" | grep -v '^$')"
	if [ -n "$REQ_COMMENT_PREFIX" ]; then
		# 行頭コメント行のみ除去。リテラル先頭一致（index==1）で正規表現エスケープ不要。
		out="$(printf '%s\n' "$out" | awk -v p="$REQ_COMMENT_PREFIX" 'index($0,p)==1{next} {print}')"
	fi
	printf '%s\n' "$out"
}
# 前提: この関数は R_FILE[$id] が実在することを前提にする（dangling id は渡さない。
# 判定ループは実在要件 reqs[] のみを回し、対象ファイルのパスは主シェル側で空白なしを担保済み）。
req_test_sha() { # <id> -> 現在ハッシュ（対象が空なら空文字）
	local id="$1" g m
	[ -n "${R_FILE[$id]:-}" ] || { printf ''; return; }   # 修正1: set -u 保護。未定義idなら安全に空を返す
	local files=()
	# ① マーカー保持ファイル ∪ test_assets glob を収集（パスは上流で空白なしを担保＝単語分割安全）
	for m in ${MARK_FILES[$id]:-}; do files+=("$m"); done
	while IFS= read -r g; do
		[ -n "$g" ] || continue
		while IFS= read -r m; do [ -e "$m" ] && files+=("$m"); done < <(compgen -G "$g" || true)
	done < <(fm_list "${R_FILE[$id]}" test_assets)
	[ "${#files[@]}" -gt 0 ] || { printf ''; return; }
	# 重複排除＋ファイルパス昇順
	local sorted
	sorted="$(printf '%s\n' "${files[@]}" | sort -u)"
	# 正規化して連結 → sha256
	{ while IFS= read -r ff; do [ -n "$ff" ] && normalize_file "$ff"; done <<< "$sorted"; } \
		| sha256sum | awk '{print $1}'
}

# ---- --sha モード（批准時の検算用。判定はせずハッシュのみ出力） ----
if [ "${1:-}" = "--sha" ]; then
	target="${2:-}"
	[ -n "$target" ] || die "使い方: --sha <R-xxx>"
	[ -n "${R_FILE[$target]:-}" ] || die "$target に対応する要件が $REQ_DIR にありません"
	req_test_sha "$target"
	exit 0
fi

# ④の適用可否をログ（再批准頻発時に運用者が原因を追えるように）
if [ -n "$REQ_COMMENT_PREFIX" ]; then
	echo "[req-coverage] §7④ 行頭コメント除去: 有効（prefix='$REQ_COMMENT_PREFIX'）"
else
	echo "[req-coverage] §7④ 行頭コメント除去: スキップ（REQ_COMMENT_PREFIX 未設定＝①②③のみ）"
fi

# ---- ベースライン健全性（B3）：S/A の登録は設定エラー、ID破損も設定エラー ----
declare -A IN_BASELINE
base_count=0
if [ -f "$BASELINE" ]; then
	while IFS= read -r line; do
		line="${line%%#*}"
		line="$(printf '%s' "$line" | tr -d '[:space:]')"
		[ -n "$line" ] || continue
		printf '%s' "$line" | grep -qE '^R-[0-9]+$' || die "$BASELINE の行が R-<数字> でない: '$line'（破損）"
		case "${R_TIER[$line]:-__UNKNOWN__}" in
			S|A) die "$BASELINE に S/A 要件 $line が登録されています（B3: S/A はベースライン免除不可）" ;;
			__UNKNOWN__) die "$BASELINE の $line に対応する要件が $REQ_DIR にありません（fail-closed）" ;;
		esac
		IN_BASELINE[$line]=1
		base_count=$(( base_count + 1 ))
	done < "$BASELINE"
fi
echo "[req-coverage] ベースライン登録数: $base_count（S/A は登録不可。減る方向のみ）"

# ---- dangling 検出：マーカーが指すIDに要件が無い/未批准なら赤 ----
declare -A MARKED
for id in "${!COVER[@]}"; do MARKED[$id]=1; done
for id in "${!ADV[@]}";   do MARKED[$id]=1; done
for id in "${!MARKED[@]}"; do
	if [ -z "${R_STATUS[$id]:-}" ]; then
		report "dangling: マーカー $id に対応する要件が $REQ_DIR に無い"
	elif [ "${R_STATUS[$id]}" != "ratified" ]; then
		report "dangling: マーカー $id が指す要件が未批准（status=${R_STATUS[$id]}）"
	fi
done

# ---- 批准済み要件の判定 ----
for id in "${reqs[@]}"; do
	[ "${R_STATUS[$id]}" = "ratified" ] || continue
	covered=0; [ "${COVER[$id]:-0}" -gt 0 ] && covered=1
	case "${R_TIER[$id]}" in
		S|A)
			[ "$covered" -eq 1 ] || report "未カバー(Tier ${R_TIER[$id]}=即赤・ベースライン猶予なし): $id"
			[ -n "${R_TR[$id]}" ] || report "妥当性未批准: $id は tests_ratified_by 未設定（B1）"
			cur="$(req_test_sha "$id")"
			if [ -z "${R_SHA[$id]}" ] || [ "${R_SHA[$id]}" = "PENDING" ]; then
				report "tests_ratified_sha 未確定: $id（S/A 必須, F1）"
			elif [ "${R_SHA[$id]}" != "$cur" ]; then
				report "批准後にテスト改変を検知: $id は再批准が必要（F1。期待=${R_SHA[$id]} 現在=$cur）"
			fi
			if [ "${R_NEG[$id]}" -eq 1 ] && [ -z "${ADV[$id]:-}" ]; then
				report "negative_space 有だが adversarial テスト未紐づけ: $id（G4）"
			fi
			;;
		B|C)
			if [ "$covered" -eq 0 ]; then
				if [ -n "${IN_BASELINE[$id]:-}" ]; then
					echo "  ⚠ 未カバー(ベースライン猶予): $id" >&2
				else
					report "未カバー: $id"
				fi
			fi
			;;
	esac
done

if [ "$fail" -ne 0 ]; then
	echo "[req-coverage] ❌ 要件トレーサビリティに問題を検出しました。" >&2
	exit 1
fi
echo "[req-coverage] ✅ 未カバー要件・妥当性・改変の問題なし。"
exit 0
