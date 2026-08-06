#!/usr/bin/env bash
# check-required-checks.sh — 必須ステータスチェックの「宣言」を検証する（共通・スタック中立）。
#
# 【なぜ宣言なのか】
# ブランチ保護の必須チェック設定は **GitHub 側にあり、リポジトリの中からは見えない**。
# 設定そのものは機械で検証できない（Administration 権限を要し、環境によって結果が変わる）。
# だが「設定できる形になっていること」なら検証できる。そこで
# `.github/required-checks.txt` に必須にすべきチェック名を宣言させ、**宣言と実装の一致**を見る。
# GitHub API は叩かない——トークンの権限に依存させないため（CI でもローカルでも同じ結果になる）。
#
# 【何を見るか】
#   ① 宣言された名前が、実在するワークフローのジョブとして定義されていること
#   ② そのジョブを持つワークフローが pull_request でトリガされること
#      必須チェックは **PR の head に対して走ったときだけ**マージ判定に現れる。
#      push でしか走らないジョブを必須にすると **PR が永久にブロックされる**。
#      そして「PR では走らないゲート」を必須のつもりで並べた状態は、緑に見えて何も守らない。
#      2026-08-06、既存プロジェクトで実際にこの形（テストが push でしか走らない）を発見した。
#   ③ ワークフロー間でジョブ名が重複しないこと
#      同じチェック名が複数のワークフローから報告されると、必須チェックの判定先が曖昧になる。
#
# 【見ないもの】
# GitHub 側の実設定との突き合わせ。これは `gh api .../branches/main/protection` で人が行う
# （手順は docs/audit/branch-protection-*.md）。**できないことを検査に混ぜない**——
# 環境によって結果が変わる検査は、赤が常態化してすぐ無視されるようになる。
#
# 【workflow_call 専用のワークフローを除外する理由】
# reusable workflow のジョブは、呼ばれると `<呼び出し側のジョブ id> / <ジョブ名>` という
# **別の文字列**になる。素の名前で衝突することはないので一意性の対象から外す。
# 逆に、呼び出し側のジョブ id は素の名前空間にいるので対象に含まれる。
#
# 【限界（承知のうえで単純にしている）】
# - matrix を使うジョブのチェック名は `job (値)` になる。使い始めたらここを拡張すること。
# - `ci / gates` のような**呼び出し先の名前は検証できない**（別リポジトリにあるため）。
#   宣言にこの形があるときは接頭辞（呼び出し側のジョブ id）だけを見る。
# - YAML パーサではなく行の形で見る（ジョブ id は2スペース、ジョブ名は4スペースの `name:`）。
#
# 使い方: check-required-checks.sh <project-root>
# 終了コード: 0=問題なし / 1=問題あり / 2=呼び出し方の誤り（fail-closed）

set -u

die() { echo "  ❌ [required-checks] $1" >&2; exit 2; }

fail=0
report() { echo "  ❌ $1"; fail=1; }

[ "$#" -eq 1 ] || die "使い方: check-required-checks.sh <project-root>（fail-closed）"
ROOT="$1"
[ -d "$ROOT" ] || die "プロジェクトルートがありません: $ROOT"

WF_DIR="$ROOT/.github/workflows"
DECL="$ROOT/.github/required-checks.txt"

# on: に指定イベントがあるか。ブロック形（on:\n  pull_request:）と配列形（on: [push, pull_request]）
# の両方を見る。`pull_request_target` を `pull_request` と誤認しないよう、区切りまで含めて照合する。
has_trigger() { # <file> <event>
	awk -v ev="$2" '
		/^on:[[:space:]]*\[/ {
			line = $0; gsub(/[^A-Za-z_]/, " ", line)
			if (line ~ ("(^| )" ev "( |$)")) found = 1
			next
		}
		/^on:[[:space:]]*(#.*)?$/ { inon = 1; next }
		inon && /^[^[:space:]#]/  { inon = 0 }
		inon && $0 ~ ("^[[:space:]]+" ev "[[:space:]]*:") { found = 1 }
		END { exit(found ? 0 : 1) }
	' "$1"
}

# ジョブのチェック名を列挙する。job-level の `name:` があればそれが、無ければジョブ id が
# チェック名になる。ステップの name は `- name:` の形なので4スペースの `name:` とは衝突しない。
job_names() { # <file>
	awk '
		/^jobs:[[:space:]]*(#.*)?$/ { injobs = 1; next }
		injobs && /^[^[:space:]#]/  { injobs = 0 }
		injobs && /^  [A-Za-z0-9_.-]+:[[:space:]]*(#.*)?$/ {
			if (id != "") print (nm != "" ? nm : id)
			id = $1; sub(/:$/, "", id); nm = ""; insteps = 0
			next
		}
		injobs && /^    steps:/ { insteps = 1 }
		injobs && !insteps && /^    name:[[:space:]]/ {
			nm = $0; sub(/^    name:[[:space:]]*/, "", nm)
			gsub(/^["\047]|["\047]$/, "", nm)
		}
		END { if (id != "") print (nm != "" ? nm : id) }
	' "$1"
}

# ---- 対象ワークフローの収集 ----------------------------------------------------
# 素の名前空間にいる（＝呼ばれる側ではない）ワークフローだけを集める。
if [ ! -d "$WF_DIR" ]; then
	if [ -f "$DECL" ] && grep -qvE '^[[:space:]]*(#|$)' "$DECL" 2>/dev/null; then
		report "$DECL に宣言がありますが .github/workflows/ がありません（走るはずのジョブが存在しません）"
		exit 1
	fi
	echo "  ℹ .github/workflows/ が無いため必須チェック宣言の検査はスキップしました（CI そのものがありません）"
	exit 0
fi

wf_files=()
for wf in "$WF_DIR"/*.yml "$WF_DIR"/*.yaml; do
	[ -f "$wf" ] || continue
	# workflow_call 専用（push / pull_request のどちらでも走らない）は接頭辞が付くので対象外
	if has_trigger "$wf" workflow_call && ! has_trigger "$wf" push && ! has_trigger "$wf" pull_request; then
		continue
	fi
	wf_files+=("$wf")
done

if [ "${#wf_files[@]}" -eq 0 ]; then
	echo "  ℹ 素の名前空間を持つワークフローがありません（workflow_call 専用のみ）。検査対象なし"
	exit 0
fi

# ---- ③ ジョブ名の一意性 --------------------------------------------------------
dups="$(
	for wf in "${wf_files[@]}"; do
		job_names "$wf" | while IFS= read -r n; do
			[ -n "$n" ] && printf '%s\t%s\n' "$n" "${wf##*/}"
		done
	done | sort | awk -F'\t' '{ if ($1 == prev) { print $1 } prev = $1 }' | sort -u
)"
if [ -n "$dups" ]; then
	while IFS= read -r n; do
		[ -n "$n" ] || continue
		where="$(for wf in "${wf_files[@]}"; do job_names "$wf" | grep -qxF "$n" && printf '%s ' "${wf##*/}"; done)"
		report "ジョブ名 '$n' が複数のワークフローで定義されています（$where）。必須チェックの判定先が曖昧になり PR が永久にブロックされます"
	done <<< "$dups"
fi

# ---- 宣言ファイル --------------------------------------------------------------
if [ ! -f "$DECL" ]; then
	report "$DECL がありません（必須チェックに何を指定すべきかがリポジトリ内に残りません。空でも作り、コメントで理由を書くこと）"
	exit 1
fi

nested_seen=0
while IFS= read -r line || [ -n "$line" ]; do
	# コメントと空行を落とし、前後の空白を削る
	line="${line%%#*}"
	line="$(printf '%s' "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
	[ -n "$line" ] || continue

	# `ci / gates` のような呼び出し先の名前は、接頭辞（呼び出し側のジョブ id）だけを見る
	target="$line"
	case "$line" in
		*/*)
			target="$(printf '%s' "${line%%/*}" | sed -e 's/[[:space:]]*$//')"
			nested_seen=1
			;;
	esac

	found_in=""
	for wf in "${wf_files[@]}"; do
		if job_names "$wf" | grep -qxF "$target"; then
			found_in="$wf"
			break
		fi
	done

	if [ -z "$found_in" ]; then
		report "宣言 '$line' に対応するジョブ '$target' がワークフローにありません（名前を変えたか、宣言の消し忘れ）"
		continue
	fi
	if ! has_trigger "$found_in" pull_request; then
		report "宣言 '$line' のジョブ '$target' は ${found_in##*/} にありますが pull_request で走りません（必須にすると PR が永久にブロックされます。トリガに pull_request を足すこと）"
	fi
done < "$DECL"

if [ "$nested_seen" = "1" ]; then
	echo "  ℹ reusable 呼び出し（'呼び出し側 / ジョブ名'）は接頭辞のみ検証しました。呼び出し先の名前は別リポジトリにあるため実行結果で確認すること"
fi

[ "$fail" -eq 0 ] || exit 1
exit 0
