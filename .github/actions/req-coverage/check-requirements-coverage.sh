#!/usr/bin/env bash
# check-requirements-coverage.sh — ratified 要件↔テストの紐づけ（カバレッジ）を機械検証する。
# 設計の正: docs/rules/requirements.md / docs/rules/tiers.md /
#           docs/rules/quality-gates.md §5（一方向ラチェット思想）。
# 既存作法踏襲: set -u・fail-closed。
# 2026-07-24 批准レス化（ADR-008）: 人間批准チェック（tests_ratified_by/B1・tests_ratified_sha/F1・F3）は
# 廃止。要件↔テストの機械照合（未カバー・dangling・G4・B3）のみを検証する。
#
# 終了コード: 0=OK / 1=要件未達（赤）/ 2=設定エラー・破損（fail-closed）。
#
# 設定（マーカー文字列はスタック依存のため PROJECT.md 由来。Makefile の req-coverage が export する）:
#   REQ_TEST_PATHS     … テストを探索するパス（空白区切り）。必須（未設定は exit 2）。
#   REQ_MARKER_RE      … req マーカー行にマッチする拡張正規表現（R-<数字> を含むこと）。必須（未設定は exit 2）。
#   ADV_MARKER_RE      … adversarial マーカー行の拡張正規表現。未設定なら adversarial 被覆なし扱い。
#
# 使い方:
#   bash scripts/check-requirements-coverage.sh            # 全要件を検証

set -u
shopt -s nullglob

# 検証対象リポジトリのルート。第1引数で受け取る（省略時はスクリプト位置から導出＝従来動作）。
# 参照方式では共通リポの common/scripts/ から各プロジェクトを検証するため、位置からの導出では
# 正しいルートに解決できない。引数を任意にしてあるのは既存の呼び出しを壊さないため（2026-07-26 フェーズ0）。
ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
[ -d "$ROOT" ] || { echo "❌ 指定されたリポジトリルートが存在しません: $ROOT" >&2; exit 2; }
cd "$ROOT" || exit 2
REQ_DIR="docs/requirements"
BASELINE=".req-coverage-baseline"

fail=0
report() { echo "  ❌ $1" >&2; fail=1; }
die()    { echo "❌ $1" >&2; exit 2; }

REQ_TEST_PATHS="${REQ_TEST_PATHS:-}"
REQ_MARKER_RE="${REQ_MARKER_RE:-}"
ADV_MARKER_RE="${ADV_MARKER_RE:-}"

[ -n "$REQ_MARKER_RE" ]  || die "REQ_MARKER_RE 未設定（PROJECT.md 由来のマーカー正規表現。fail-closed）"
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
declare -A R_TIER R_STATUS R_NEG R_FILE
reqs=()
for f in "$REQ_DIR"/R-*.md; do
	# 配布テンプレは要件ではないため検証対象外。除外は固定名 R-000-template.md に限定する
	# （docs/rules/requirements.md がこの名を規定）。それ以外の場所・名前で tier がプレースホルダ/
	# 不正値でも従来どおり die（exit 2）＝fail-closed を維持する（中身ベースの除外は fail-open のため不採用）。
	[ "$(basename "$f")" = "R-000-template.md" ] && continue
	id="$(fm_scalar "$f" id)"
	tier="$(fm_scalar "$f" tier)"
	status="$(fm_scalar "$f" status)"
	printf '%s' "$id" | grep -qE '^R-[0-9]+$' || die "front-matter id が R-<数字> でない: $f （'$id'）"
	case "$tier" in S|A|B|C) ;; *) die "front-matter tier が S|A|B|C でない: $f （'$tier'）" ;; esac
	[ -z "${R_TIER[$id]:-}" ] || die "要件ID重複: $id（$f と ${R_FILE[$id]}）"
	reqs+=("$id")
	R_TIER[$id]="$tier"; R_STATUS[$id]="$status"
	R_FILE[$id]="$f"
	if [ -n "$(fm_list "$f" negative_space | head -n1)" ]; then R_NEG[$id]=1; else R_NEG[$id]=0; fi
done

# ---- テスト走査：マーカー→被覆／adversarial被覆 ----
declare -A COVER ADV
read -r -a _paths <<< "$REQ_TEST_PATHS"
test_files=()
for p in "${_paths[@]}"; do
	[ -e "$p" ] || continue
	while IFS= read -r tf; do
		# 空白を含む対象パスは決定論を壊すため fail-closed（主シェルなので die が全体を止める）
		case "$tf" in *[[:space:]]*) die "テスト対象パスに空白が含まれます: '$tf'（決定論のため空白禁止）" ;; esac
		test_files+=("$tf")
	done < <(find "$p" -type f | sort)
done
for tf in "${test_files[@]}"; do
	while IFS= read -r rid; do
		COVER[$rid]=$(( ${COVER[$rid]:-0} + 1 ))
	done < <(grep -oE "$REQ_MARKER_RE" "$tf" 2>/dev/null | grep -oE 'R-[0-9]+' | sort -u)
	if [ -n "$ADV_MARKER_RE" ]; then
		while IFS= read -r aid; do
			ADV[$aid]=1
		done < <(grep -oE "$ADV_MARKER_RE" "$tf" 2>/dev/null | grep -oE 'R-[0-9]+' | sort -u)
	fi
done

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

# ---- dangling 検出：マーカーが指すIDに要件が無い/ratifiedでないなら赤 ----
declare -A MARKED
for id in "${!COVER[@]}"; do MARKED[$id]=1; done
for id in "${!ADV[@]}";   do MARKED[$id]=1; done
for id in "${!MARKED[@]}"; do
	if [ -z "${R_STATUS[$id]:-}" ]; then
		report "dangling: マーカー $id に対応する要件が $REQ_DIR に無い"
	elif [ "${R_STATUS[$id]}" != "ratified" ]; then
		report "dangling: マーカー $id が指す要件が ratified でない（status=${R_STATUS[$id]}）"
	fi
done

# ---- 批准済み要件の判定 ----
for id in "${reqs[@]}"; do
	[ "${R_STATUS[$id]}" = "ratified" ] || continue
	covered=0; [ "${COVER[$id]:-0}" -gt 0 ] && covered=1
	case "${R_TIER[$id]}" in
		S|A)
			[ "$covered" -eq 1 ] || report "未カバー(Tier ${R_TIER[$id]}=即赤・ベースライン猶予なし): $id"
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
echo "[req-coverage] ✅ 未カバー要件・danglingの問題なし。"
exit 0
