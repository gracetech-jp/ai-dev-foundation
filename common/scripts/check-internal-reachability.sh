#!/usr/bin/env bash
# check-internal-reachability.sh — **遮断してはいけない内部通信**が実際に通ることを測る（共通・スタック中立）。
#
# 【この検査だけ方向が逆である】
# ADR-013 第1層の実測（verify-isolation.sh）は「許可外へ出られないこと」を測る。
# ここだけは逆で、**通るべきものが通ること**を測る。compose 方式の devcontainer では、
# ファイアウォールが兄弟コンテナ（backend / db / mailpit 等）への内部通信まで止めると、
# `make test` も E2E も全滅する。**遮断のしすぎは、遮断の不足と同じくらい確実に事故になる。**
# 遮断側だけを測っていると「全部止めても緑」になり、この失敗を1件も捕まえられない。
#
# 【到達先はプロジェクト側の宣言から読む】
# サービス名・ポートはプロジェクト固有で、共通側に書けない。共通側が持つのは**判定ロジックだけ**で、
# 何へ到達すべきかは各プロジェクトが宣言する（ADR-010 の参照方式。実体は1つ）。
#   宣言: <project-root>/.devcontainer/internal-targets.txt
#   書式: 1行1到達先。`#` 以降はコメント。空行は無視
#     http://backend:8000/health        … HTTP（https も可）
#     db:5432                            … TCP 接続のみ
#
# 【HTTP ステータスは見ない】
# 404 でも 500 でも「ネットワーク経路が通っている」ことの証明にはなる。ここが測るのは**到達性**で
# あって、アプリの健全性ではない。両者を混ぜると、アプリのバグでファイアウォールを疑うことになる。
#
# 【宣言があるのに到達先が0件なら赤にする】
# 全部コメントアウトすれば緑になる検査は、いつのまにか消える。宣言ファイルを置いた時点で
# 「このプロジェクトには通すべき内部通信がある」と言っているので、0件は矛盾として扱う。
# 宣言ファイル**そのもの**が無い場合だけが未判定（compose を使っていないプロジェクト）。
#
# 【監査（audit-all）から呼ばないこと】
# これは動いているコンテナの中でしか意味を持たない実測である。CI には兄弟コンテナが居らず、
# 必ず赤になる。呼び出し元は verify-isolation.sh（Rebuild のたびに人が1回流すもの）に限る。
#
# 使い方: check-internal-reachability.sh <project-root>
# 終了コード: 0=問題なし（未判定を含む） / 1=到達できない / 2=呼び出し方・宣言の誤り（fail-closed）

set -u

DECL_REL=".devcontainer/internal-targets.txt"
CONNECT_TIMEOUT=5
MAX_TIME=15
TCP_TIMEOUT=5

die() { echo "  ❌ [internal-reachability] $1" >&2; exit 2; }

fail=0
report() { echo "  ❌ $1"; fail=1; }

[ "$#" -eq 1 ] || die "使い方: check-internal-reachability.sh <project-root>（fail-closed）"
ROOT="$1"
[ -d "$ROOT" ] || die "プロジェクトルートがありません: $ROOT"

DECL="$ROOT/$DECL_REL"
if [ ! -f "$DECL" ]; then
	echo "  ℹ $DECL_REL が無いため内部到達性は未判定（compose 方式でないプロジェクト）"
	exit 0
fi

# 宛先の検証は**全件まとめて先に**行う。書式の誤りを「到達できない」と混同すると、
# タイポをファイアウォールの問題として調べることになる。
targets=()
lineno=0
while IFS= read -r raw || [ -n "$raw" ]; do
	lineno=$((lineno + 1))
	line="${raw%%#*}"                      # コメント除去
	line="$(printf '%s' "$line" | tr -d '[:space:]')"
	[ -n "$line" ] || continue
	case "$line" in
		http://*|https://*)
			# ホスト部が空の指定（http:// だけ等）を弾く
			rest="${line#*://}"
			[ -n "${rest%%/*}" ] || die "$DECL_REL:$lineno ホスト名がありません: $raw"
			;;
		*:*)
			host="${line%:*}"; port="${line##*:}"
			printf '%s' "$host" | grep -qE '^[A-Za-z0-9._-]+$' \
				|| die "$DECL_REL:$lineno ホスト名が不正です: $raw"
			printf '%s' "$port" | grep -qE '^[0-9]+$' \
				|| die "$DECL_REL:$lineno ポートが数値ではありません: $raw"
			[ "$port" -ge 1 ] && [ "$port" -le 65535 ] \
				|| die "$DECL_REL:$lineno ポートが範囲外です: $raw"
			;;
		*)
			die "$DECL_REL:$lineno 書式が不正です（http(s):// か host:port）: $raw"
			;;
	esac
	targets+=("$line")
done < "$DECL"

if [ "${#targets[@]}" -eq 0 ]; then
	report "$DECL_REL に到達先が1件もありません（宣言だけあって検査が空回りしています）"
	echo "     → 通すべき内部通信が無いなら、宣言ファイルごと削除して未判定にすること"
	exit 1
fi

http_probe() { curl --connect-timeout "$CONNECT_TIMEOUT" --max-time "$MAX_TIME" -s -o /dev/null "$1"; }
# nc に依存しないよう bash の /dev/tcp を使う（Debian 系の bash は有効。実測済み）。
# host / port は上で正規表現検証済みなので、この展開に任意の文字列は入らない。
tcp_probe() { timeout "$TCP_TIMEOUT" bash -c "exec 3<>/dev/tcp/$1/$2" 2>/dev/null; }

for t in "${targets[@]}"; do
	case "$t" in
		http://*|https://*)
			if http_probe "$t"; then
				echo "  ✅ $t へ到達できる"
			else
				report "$t へ到達できません（内部通信が遮断されています）"
			fi
			;;
		*)
			if tcp_probe "${t%:*}" "${t##*:}"; then
				echo "  ✅ $t へ到達できる"
			else
				report "$t へ到達できません（内部通信が遮断されています）"
			fi
			;;
	esac
done

if [ "$fail" -ne 0 ]; then
	echo "     → 遮断のしすぎである。init-firewall.sh が内部ネットワークの CIDR を"
	echo "        許可しているか確認する（compose の既定は /16。/24 決め打ちだと兄弟を取りこぼす）"
	exit 1
fi
exit 0
