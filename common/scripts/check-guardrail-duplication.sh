#!/usr/bin/env bash
# check-guardrail-duplication.sh — ガードレール二重化の突合（ADR-012 決定4）。共通・スタック中立。
#
# 【何を守るか】
# 破壊的コマンドの判定は第2層（permissions.deny）と第3層（PreToolUse フック）の両方に置く。
# 冗長化の根拠は「片方が漏れるから」ではなく、**2つの層が独立に失敗する**こと——
# deny は例外を書けずに失敗し、フックは見つからずに失敗する。原因が共通していないため、
# simplicity-in-security（同一理由で壊れる重複は避ける）の例外にあたる。
# 逆に言えば **片側だけが消えた瞬間に二重化は成立しなくなる**。しかも消えても何も起きない
# （テストは緑、コンテナは動く）。人手のレビューでは検出できないので機械で見る。
#
# 【なぜ共通側に抽出したか（2026-08-08）】
# この検査は**基盤の audit-consistency.sh (14) と配布雛形の (5) に別々の実装があり、
# 判定の正本である DUAL_LAYER / DENY_CORE 配列を両方が持っていた**。基盤側の実装自身が
# 「新しい正本ファイルは作らない。作ると4箇所目の重複になる」と書いているのに、
# 配布側にもう1つ生えていた。ここに1本化して、配列を1箇所にする。
#
# 【基盤リポと生成プロジェクトで見る範囲が違う】
# 判定の中身は同じでも、成立条件が違う。
#   基盤リポ    … 第3層の実体（.claude/scripts/guard-dangerous.sh）と配布用 settings.json 群を持つ
#   プロジェクト … 第3層はコンテナのマウント越し。settings.json は自分の1本だけ。
#                  代わりに「フックの複製が生えていないか」「マウントが生きているか」を見る必要がある
# 判別はプロジェクトルートに `profiles/_base/` が有るかで行う（R-001-3 が採る判別と同じ）。
#
# 使い方: check-guardrail-duplication.sh <project-root>
# 終了コード: 0=問題なし / 1=退化を検出 / 2=呼び出し方の誤り（fail-closed）

set -u

# 判定ID:必須の deny ルール。フック側は `# @dual-layer: <ID>` のマーカーで対応づける。
# **この配列がこの検査の正本である。** 増やすときはフック側のマーカーも同時に置くこと。
DUAL_LAYER=(
	"A2:Bash(git push:*)"              # force push（push 全体を deny しているため --force も覆える）
	"A3:Bash(git reset *--hard*)"      # 履歴破棄。フラグ位置に依存しない形
	"A4:Bash(git clean -f*)"           # 作業ツリー破棄。-n/--dry-run は通す（例外はフック側が持つ）
	"A6:Bash(git checkout -- *)"       # パス指定による変更破棄
)
# 「1件でもあれば緑」では大半が消えても素通りするため、消えたら意味を失うものを個別に要求する。
# 追加時は理由を1行残すこと。
DENY_CORE=(
	"Bash(rm -rf:*)"          # 再帰強制削除の代表形
	"Bash(sudo rm:*)"         # sudo 経由の削除
	"Read(**/.env)"           # 秘密ファイルのツール経路（bash 経路はフックが担う）
	"Read(**/.ssh/**)"        # 秘密鍵
	"Read(**/.aws/**)"        # クラウド認証情報
)

die() { echo "  ❌ [guardrail-dup] $1" >&2; exit 2; }

fail=0
report() { echo "  ❌ $1"; fail=1; }

[ "$#" -eq 1 ] || die "使い方: check-guardrail-duplication.sh <project-root>（fail-closed）"
ROOT="$1"
[ -d "$ROOT" ] || die "プロジェクトルートがありません: $ROOT"

# 基盤リポか否か。R-001-3 の判別（プロジェクトルートに profiles/_base/ が無ければプロジェクト）と揃える。
is_foundation=0
[ -d "$ROOT/profiles/_base" ] && is_foundation=1

# jq が無いと deny を読めない。**黙って飛ばさない**——旧・基盤側の実装は jq 不在時に
# 何も報告せず素通りしていた（2026-08-08 の抽出で判明。配布側は fail-closed だった）。
# 弱いほうに揃えると検査ごと消えるので、強いほう（fail-closed）を採る。
command -v jq >/dev/null 2>&1 \
	|| { report "jq が無いため deny を検証できません（fail-closed）"; exit 1; }

# ── 第2層: 検証対象の settings.json を決める ──────────────────────────────
settings=()
main_settings="$ROOT/.claude/settings.json"
if [ -f "$main_settings" ]; then
	settings+=("$main_settings")
else
	report ".claude/settings.json がありません（第2層の実体。ルール無しで動きます）"
fi
if [ "$is_foundation" -eq 1 ]; then
	# 基盤は配布用の settings.json も持つ。**4本すべてに同じ deny が要る**——
	# 1本だけ直しても、そこから生まれたプロジェクトはルール無しになる。
	[ -f "$ROOT/profiles/_base/.claude/settings.json" ] && settings+=("$ROOT/profiles/_base/.claude/settings.json")
	for pset in "$ROOT"/profiles/*/files/.claude/settings.json; do
		[ -f "$pset" ] && settings+=("$pset")
	done
fi

deny_has() { # <settings.json> <ルール文字列>
	jq -e --arg r "$2" '.permissions.deny // [] | index($r)' "$1" >/dev/null 2>&1
}

for sf in ${settings[@]+"${settings[@]}"}; do
	rel="${sf#"$ROOT"/}"
	for entry in "${DUAL_LAYER[@]}"; do
		id="${entry%%:*}"; rule="${entry#*:}"
		deny_has "$sf" "$rule" \
			|| report "二重化の退化: $rel の deny に判定 $id の '$rule' がありません（第2層から判定が消えています）"
	done
	for core in "${DENY_CORE[@]}"; do
		deny_has "$sf" "$core" \
			|| report "deny コアの退化: $rel の deny に '$core' がありません"
	done
done

# ── 第3層: フック本体との突合 ─────────────────────────────────────────────
# 基盤は自分の中に実体を持つ。プロジェクトはマーカーを上方探索して共通側を見る。
if [ "$is_foundation" -eq 1 ]; then
	guard="$ROOT/.claude/scripts/guard-dangerous.sh"
	[ -f "$guard" ] || { report "$guard がありません（第3層の実体が消えています。ADR-012）"; guard=""; }
else
	d="$ROOT"; guard=""
	while [ "$d" != "/" ]; do
		if [ -f "$d/.ai-dev-foundation-root" ]; then guard="$d/.claude/scripts/guard-dangerous.sh"; break; fi
		d="$(dirname "$d")"
	done
	if [ -z "$guard" ]; then
		# **黙って飛ばさず理由を出す。** 無言のスキップは「作動していないゲート」になる。
		echo "  ℹ 共通基盤が見つからないため第3層の突合はスキップしました（CI の単独チェックアウト等。第2層は上で検証済み）"
	elif [ ! -r "$guard" ]; then
		report "共通基盤は見つかりましたが $guard が読めません（第3層が配られていません）"
		guard=""
	fi
fi

if [ -n "$guard" ] && [ -r "$guard" ]; then
	for entry in "${DUAL_LAYER[@]}"; do
		id="${entry%%:*}"
		grep -qE "^[[:space:]]*#[[:space:]]*@dual-layer:[[:space:]]*${id}([^0-9A-Za-z]|$)" "$guard" \
			|| report "二重化の退化: フックに判定 $id のマーカーがありません（第3層から判定が消えています。ADR-012 決定4）"
	done
	# 逆方向。実装だけ増えて突合が空回りするのを防ぐ（対応表に無いマーカーを検出）。
	while IFS= read -r id; do
		[ -n "$id" ] || continue
		found=0
		for entry in "${DUAL_LAYER[@]}"; do [ "${entry%%:*}" = "$id" ] && found=1; done
		[ "$found" -eq 1 ] \
			|| report "二重化の突合漏れ: フックに @dual-layer: $id があるのに DUAL_LAYER に登録がありません"
	done < <(sed -n 's/^[[:space:]]*#[[:space:]]*@dual-layer:[[:space:]]*\([0-9A-Za-z]*\).*/\1/p' "$guard" | sort -u)
fi

# ── プロジェクト側だけの検査 ──────────────────────────────────────────────
# 基盤は第3層の実体とフック定義を**正当に持つ**ので対象外。
if [ "$is_foundation" -eq 0 ]; then
	# フック定義をプロジェクト側へ置き直していないか。$CLAUDE_PROJECT_DIR は**起動ディレクトリ**を
	# 指すため、サブディレクトリから起動するとフックが見つからず無警告で素通しする
	# （ADR-012 フェーズ2でユーザースコープ1本に集約した経緯）。
	if [ -f "$main_settings" ] && jq -e '.hooks // {} | length > 0' "$main_settings" >/dev/null 2>&1; then
		report ".claude/settings.json にフック定義があります（フックは共通側のユーザースコープ1本に集約する。ADR-012）"
	fi
	# フック本体の複製が生えていないか
	if [ -d "$ROOT/.claude/scripts" ] && [ -n "$(find "$ROOT/.claude/scripts" -type f 2>/dev/null)" ]; then
		report ".claude/scripts/ にフック複製があります（実体は共通側に1つだけ。ADR-012 フェーズ2）"
	fi
	# 配布経路（共通 .claude のマウント）が生きているか。ここが消えると、
	# フックもルールも無いまま無警告で起動する。
	dist_mount_ok=0
	for dc in ".devcontainer/devcontainer.json" ".devcontainer/compose.yaml"; do
		[ -f "$ROOT/$dc" ] || continue
		grep -q '/home/node/\.claude' "$ROOT/$dc" && dist_mount_ok=1
	done
	[ "$dist_mount_ok" = "1" ] \
		|| report ".devcontainer が共通 .claude を /home/node/.claude へマウントしていません（フックもルールも配られません。ADR-012）"
fi

[ "$fail" -eq 0 ] || exit 1
exit 0
