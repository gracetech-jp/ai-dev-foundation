#!/usr/bin/env bash
# check-foundation-ref.sh — reusable workflow の `uses: ...@X` と `foundation-ref: Y` の一致を見る。
#
# 【なぜ二重に書く羽目になっているか】
# ADR-011 §1-3 は「`foundation-ref` 未指定なら `github.job_workflow_sha` が
# 呼ばれた reusable と同じコミットを指す」前提で、呼び出し側に ref を二重に書かせない設計だった。
# **2026-08-06 の実測でこれが崩れた**——`job_workflow_sha` も `job_workflow_ref` も空で、
# 未指定だと共通基盤の checkout が既定ブランチへ落ちる。つまり `@v2` でピン止めしても
# **main のコードでゲートが回る**（計画書 §8-5）。やむなく ref を明示する運用にした。
#
# 【なぜ機械で見るのか】
# 二重に書くものは必ずずれる。しかも**ずれても赤くならない**——ゲートは走り、緑になる。
# 違うのは「どの版のゲートで検査したか」だけで、症状が出ない。
# 版がずれたまま緑を出し続ける状態は、この基盤が繰り返し潰してきた失敗類型そのものなので、
# 一致を機械で強制する。
#
# 【見る形】
#   uses: <org>/<repo>/.github/workflows/service-ci.yml@<X>
#   with:
#     foundation-ref: <Y>            … X == Y であること
#     foundation-ref: ${{ inputs.foundation-ref }}
#                                    … 同ファイルの workflow_dispatch 入力の default と X を比べる
#                                      （dispatch で別 ref を渡して試せる形を許すため）
#
# 使い方: check-foundation-ref.sh <project-root>
# 終了コード: 0=問題なし / 1=問題あり / 2=呼び出し方の誤り（fail-closed）

set -u

die() { echo "  ❌ [foundation-ref] $1" >&2; exit 2; }

fail=0
report() { echo "  ❌ $1"; fail=1; }

[ "$#" -eq 1 ] || die "使い方: check-foundation-ref.sh <project-root>（fail-closed）"
ROOT="$1"
[ -d "$ROOT" ] || die "プロジェクトルートがありません: $ROOT"

WF_DIR="$ROOT/.github/workflows"
[ -d "$WF_DIR" ] || exit 0

# workflow_dispatch 入力 foundation-ref の default 値（無ければ空）
dispatch_default() { # <file>
	awk '
		/^[[:space:]]{6}foundation-ref:[[:space:]]*(#.*)?$/ { inblk = 1; next }
		inblk && /^[[:space:]]{0,6}[A-Za-z_-]+:/ { inblk = 0 }
		inblk && /^[[:space:]]{8}default:[[:space:]]/ {
			v = $0; sub(/^[[:space:]]*default:[[:space:]]*/, "", v)
			sub(/[[:space:]]*#.*$/, "", v)          # 行末コメントは値ではない
			sub(/[[:space:]]+$/, "", v)
			gsub(/^["\047]|["\047]$/, "", v); print v; exit
		}
	' "$1"
}

for wf in "$WF_DIR"/*.yml "$WF_DIR"/*.yaml; do
	[ -f "$wf" ] || continue
	rel="${wf#"$ROOT"/}"

	# 共通基盤の reusable を呼んでいるか（呼んでいなければ対象外）
	uses_ref="$(grep -oE 'uses:[[:space:]]*[^[:space:]]+/\.github/workflows/service-ci\.yml@[^[:space:]]+' "$wf" \
		| head -1 | sed 's/.*@//')"
	[ -n "$uses_ref" ] || continue

	# 値のある行だけを拾う。**値なしの `foundation-ref:` は workflow_dispatch の入力宣言**であり、
	# `with:` で渡している行とは別物（先頭一致で拾うと宣言のほうを掴んで誤検出する）。
	# 行末コメントは値ではない（ref に `#` は現れないので落として構わない）
	with_ref="$(grep -oE '^[[:space:]]*foundation-ref:[[:space:]]*[^[:space:]#].*$' "$wf" \
		| head -1 | sed -e 's/^[[:space:]]*foundation-ref:[[:space:]]*//' -e 's/[[:space:]]*#.*$//' -e 's/[[:space:]]*$//')"

	if [ -z "$with_ref" ]; then
		report "$rel が service-ci.yml を @${uses_ref} で呼んでいますが foundation-ref がありません（共通基盤の checkout が既定ブランチへ落ち、ピン止めが無効になります。計画書 §8-5）"
		continue
	fi

	# 式で渡している場合は dispatch 入力の default と突き合わせる
	# `{{` で式かどうかを見る（`${{ ... }}` の一部。ドル記号を書かないのは
	# シェルの展開・lint の誤検知を避けるため。ref 名に `{{` は現れない）
	case "$with_ref" in
		*'{{'*)
			resolved="$(dispatch_default "$wf")"
			if [ -z "$resolved" ]; then
				report "$rel の foundation-ref が式ですが、既定値をたどれません（workflow_dispatch 入力の default を書くこと）"
				continue
			fi
			with_ref="$resolved"
			;;
	esac

	if [ "$uses_ref" != "$with_ref" ]; then
		report "$rel で ref がずれています: uses は @${uses_ref}、foundation-ref は ${with_ref}（reusable の定義と、実際に checkout される共通基盤の版が食い違います）"
	fi
done

[ "$fail" -eq 0 ] || exit 1
exit 0
