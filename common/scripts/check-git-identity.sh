#!/usr/bin/env bash
# check-git-identity.sh — コミット identity のローカル上書きを検出する（共通・スタック中立）。
#
# 【なぜ要るのか】
# 2026-08-08、sumai-desk の `.git/config` が `user.email` をローカル上書きしており、
# **346 件が個人アドレスで記録されていた**。global には法人アドレスが入っていたが、
# local が勝つ。厄介なのは症状が出ないことである——
#   - コミットは成功する（エラーにならない）
#   - CI も赤くならない（識別子は品質ゲートの対象外）
#   - GitHub 上でも本人のコミットとして表示される（アドレスがアカウントに紐づいていれば）
# **気づく契機が1つも無い。** だから機械で見る。
#
# 【値そのものは検査しない】
# 「正しいアドレス」を共通側が知る形にすると、共同作業者・別法人の案件・OSS への寄与で
# 必ず破綻する。共通資産に個人の identity を持たせないこと自体が要件である。
# ここが見るのは **local が存在し、global と食い違っているか**だけで、何が正しいかは判断しない。
# 上書きが正当な場合もある（案件ごとにアドレスを変える運用）——だから「違う」ことを報せる。
#
# 【global 未設定なら赤にしない】
# CI のランナーは global の identity を持たない。落とすと必ず赤になり、すぐ無視される検査になる。
# 比較対象が無い以上「上書きされている」とは言えないので、未判定にする
# （check-git-hooks.sh が CI でフックを判定しないのと同じ理由）。
#
# 【user.signingkey などを見ない理由】
# リポジトリごとに署名鍵を変えるのは正当な運用である。ここで見るのは**コミットに刻まれる
# 名前とアドレス**、すなわち user.email / user.name の2つに限る。
#
# 使い方: check-git-identity.sh <project-root>
# 終了コード: 0=問題なし（未判定を含む） / 1=上書きを検出 / 2=呼び出し方の誤り（fail-closed）

set -u

# コミットに刻まれるもの。ここを増やすときは「上書きが常に誤りか」を確かめること。
KEYS=(user.email user.name)

die() { echo "  ❌ [git-identity] $1" >&2; exit 2; }

fail=0
report() { echo "  ❌ $1"; fail=1; }

[ "$#" -eq 1 ] || die "使い方: check-git-identity.sh <project-root>（fail-closed）"
ROOT="$1"
[ -d "$ROOT" ] || die "プロジェクトルートがありません: $ROOT"

# 自分自身がリポジトリのトップでなければ判定しない。上位リポジトリの一部（生成直後のサービス等）を
# 見ると、**別のリポジトリの .git/config を評価して緑にする**ことになる（check-git-hooks.sh と同じ理由）。
toplevel="$(git -C "$ROOT" rev-parse --show-toplevel 2>/dev/null || true)"
if [ -z "$toplevel" ]; then
	echo "  ℹ $ROOT は git リポジトリではないため identity は未判定"
	exit 0
fi
if [ "$(cd "$toplevel" && pwd -P)" != "$(cd "$ROOT" && pwd -P)" ]; then
	echo "  ℹ $ROOT は単独の git リポジトリではないため identity は未判定（上位リポジトリ側が見ます）"
	exit 0
fi

for key in "${KEYS[@]}"; do
	local_val="$(git -C "$ROOT" config --local --get "$key" 2>/dev/null || true)"
	[ -n "$local_val" ] || continue          # ローカル上書きが無い＝正常な形

	global_val="$(git -C "$ROOT" config --global --get "$key" 2>/dev/null || true)"
	if [ -z "$global_val" ]; then
		# 比較対象が無い。CI のランナーはここに来る。
		echo "  ℹ $key はローカル設定のみで global が無いため未判定（比較対象がありません）"
		continue
	fi

	if [ "$local_val" != "$global_val" ]; then
		report "$key がローカル設定で上書きされています: '$local_val'（global: '$global_val'）"
	fi
done

if [ "$fail" -ne 0 ]; then
	echo "     → このリポジトリのコミットだけ別の identity で記録されます。エラーにならず"
	echo "        GitHub 上も本人のコミットに見えるため、気づく契機がありません"
	echo "     → 意図した上書きでなければ削除する:"
	echo "        git -C <repo> config --local --unset user.email"
	echo "        git -C <repo> config --local --unset user.name"
	echo "     → 意図した上書きなら、その理由をリポジトリの README か PROJECT.md に残すこと"
	exit 1
fi
exit 0
