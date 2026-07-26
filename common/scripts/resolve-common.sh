#!/usr/bin/env bash
# resolve-common.sh — 共通基盤リポジトリのルートを解決する唯一の起点。
#
# 参照方式（各プロジェクトは共通基盤の複製を持たず参照する）では、Make・Docker・シェル
# スクリプトのすべてが「共通基盤はどこにあるか」を知る必要がある。階層の深さを仮定すると
# 配置換えで壊れるため、マーカーファイル .ai-dev-foundation-root を上方向に探索して決める。
#
# 使い方:
#   source /path/to/resolve-common.sh
#   COMMON_ROOT="$(resolve_common_root)"          # 起点は $PWD
#   COMMON_ROOT="$(resolve_common_root "$ROOT")"  # 起点を明示
#
# 見つからなければ非ゼロで終了する（fail-closed）。見つからない状態を「共通ルール無し」で
# 素通しさせないこと。無警告の欠落こそが、この基盤が繰り返し潰してきた失敗類型である。

# shellcheck disable=SC2148  # source 専用のためシバンに依存しない（上のシバンは lint 用）

MARKER_NAME=".ai-dev-foundation-root"

resolve_common_root() {
	local d="${1:-$PWD}"
	d="$(cd "$d" 2>/dev/null && pwd)" || {
		echo "resolve-common: 起点ディレクトリに移動できません: ${1:-$PWD}" >&2
		return 2
	}
	while [ "$d" != "/" ]; do
		if [ -f "$d/$MARKER_NAME" ]; then
			printf '%s\n' "$d"
			return 0
		fi
		d="$(dirname "$d")"
	done
	# ルート直下も見る（/ で探索を打ち切ると / 直下の配置を取りこぼすため）
	if [ -f "/$MARKER_NAME" ]; then
		printf '%s\n' "/"
		return 0
	fi
	echo "resolve-common: 共通基盤のルート（$MARKER_NAME）が見つかりません。" >&2
	echo "                このリポジトリが共通基盤リポジトリの配下に置かれているか確認してください。" >&2
	return 1
}
