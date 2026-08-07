#!/usr/bin/env bash
# 整合性監査（サービス雛形）— docs/rules/consistency.md の「監査スクリプトの3層構成」に沿って
# 各サービスが中身を肉付けする。問題があれば非ゼロで終了する（pre-push / CI から呼ばれる）。

set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

fail=0
report() { echo "  ❌ $1"; fail=1; }

echo "[audit] (1) 軽量grep整合性..."
# TODO: 過去不具合の再発防止・層間の対応漏れ検出をここに追加する。

echo "[audit] (2) 構造的不変条件..."
# TODO: モデル/設定から導かれる「常に成り立つべき条件」を検証する。

echo "[audit] (3) スキーマdrift..."
# TODO: 実データモデルとマイグレーションのズレを検証する（実環境が必要）。

echo "[audit] (4) リネーム残渣スキャン（データ駆動）..."
# 旧名→新名のリネームを行ったら "旧名|新名" を1行追加する。
renames=(
	# 例: "oldFieldName|newFieldName"
)
# `[@]+...` は空配列+set -u で bash 4.3 以前が unbound エラーになるのを防ぐイディオム
for pair in ${renames[@]+"${renames[@]}"}; do
	old="${pair%%|*}"; new="${pair##*|}"
	hits=$(grep -rn --exclude-dir=.git --exclude-dir=node_modules --exclude="audit-consistency.sh" -- "$old" "$ROOT" 2>/dev/null || true)
	if [ -n "$hits" ]; then
		report "リネーム残渣: 旧名 '$old'（→ '$new'）が残存:"
		# shellcheck disable=SC2001  # 各行への固定プレフィックス付与は sed が最も明瞭
		echo "$hits" | sed 's/^/       /'
	fi
done

# （旧(5) CODEOWNERS 検査は 2026-07-24 の批准レス化（ADR-008）で撤去。要件パスの人間レビュー必須化
#   そのものを廃止したため。チーム化でレビュー運用を再導入する場合は ADR-008 を見直して復活させる）

echo "[audit] (5) ガードレール二重化の突合（ADR-012 決定4）..."
# 破壊的コマンドの判定は第2層（permissions.deny）と第3層（PreToolUse フック）の両方に置く。
# 冗長化の根拠は「片方が漏れるから」ではなく、**2つの層が独立に失敗する**こと——
# deny は例外を書けずに失敗し、フックは見つからずに失敗する。
# 片側が消えても何も起きない（テストは緑、コンテナは動く）ため、機械で見る。
#
# このリポジトリ側で常に検証できるのは次の3点。フック本体は共通側（ユーザースコープ）にあり、
# CI ではチェックアウトされないため、そちらとの突合は解決できたときだけ行う。
# **解決できないときは黙って飛ばさず、理由を1行出す**（無言のスキップは「作動していないゲート」になる）。
DIST_SETTINGS=".claude/settings.json"
# 判定ID:この deny ルールが必須（フック側は共通リポの guard-dangerous.sh に同じIDのマーカーを持つ）
DUAL_LAYER=(
	"A2:Bash(git push:*)"
	"A3:Bash(git reset *--hard*)"
	"A4:Bash(git clean -f*)"
	"A6:Bash(git checkout -- *)"
)
# これが消えたら意味を失うもの（「1件でもあれば緑」では大半が消えても素通りする）
DENY_CORE=(
	"Bash(rm -rf:*)"
	"Bash(sudo rm:*)"
	"Read(**/.env)"
	"Read(**/.ssh/**)"
	"Read(**/.aws/**)"
)
if [ ! -f "$ROOT/$DIST_SETTINGS" ]; then
	report "$DIST_SETTINGS がありません（第2層の実体。プロジェクトはルール無しで動きます）"
elif ! command -v jq >/dev/null 2>&1; then
	report "jq が無く $DIST_SETTINGS の deny を検証できません（fail-closed）"
else
	deny_has() { jq -e --arg r "$1" '.permissions.deny // [] | index($r)' "$ROOT/$DIST_SETTINGS" >/dev/null 2>&1; }
	for entry in "${DUAL_LAYER[@]}"; do
		id="${entry%%:*}"; rule="${entry#*:}"
		deny_has "$rule" || report "二重化の退化: $DIST_SETTINGS の deny に判定 $id の '$rule' がありません（第2層が消えています）"
	done
	for core in "${DENY_CORE[@]}"; do
		deny_has "$core" || report "deny コアの退化: $DIST_SETTINGS の deny に '$core' がありません"
	done
	# フック定義をプロジェクト側に置き直していないか（$CLAUDE_PROJECT_DIR は**起動ディレクトリ**を指すため、
	# サブディレクトリから起動するとフックが見つからず無警告で素通しする。ADR-012 フェーズ2で
	# ユーザースコープ1本に集約した経緯がある）
	if jq -e '.hooks // {} | length > 0' "$ROOT/$DIST_SETTINGS" >/dev/null 2>&1; then
		report "$DIST_SETTINGS にフック定義があります（フックは共通側のユーザースコープ1本に集約する。ADR-012）"
	fi
fi
# フック本体の複製が生えていないか
if [ -d "$ROOT/.claude/scripts" ] && [ -n "$(find "$ROOT/.claude/scripts" -type f 2>/dev/null)" ]; then
	report ".claude/scripts/ にフック複製があります（実体は共通側に1つだけ。ADR-012 フェーズ2）"
fi
# 配布経路（共通 .claude のユーザースコープ・マウント）が生きているか。
# ここが消えると、フックもルールも無いまま無警告で起動する。
for dc in ".devcontainer/devcontainer.json" ".devcontainer/compose.yaml"; do
	[ -f "$ROOT/$dc" ] || continue
	grep -q '/home/node/\.claude' "$ROOT/$dc" && dist_mount_ok=1
done
[ "${dist_mount_ok:-0}" = "1" ] \
	|| report ".devcontainer が共通 .claude を /home/node/.claude へマウントしていません（フックもルールも配られません。ADR-012）"
# 共通側フックとの突合（マーカーを上方探索して解決できたときだけ）
fw_dir="$ROOT"
fw_guard=""
while [ "$fw_dir" != "/" ]; do
	if [ -f "$fw_dir/.ai-dev-foundation-root" ]; then
		fw_guard="$fw_dir/.claude/scripts/guard-dangerous.sh"
		break
	fi
	fw_dir="$(dirname "$fw_dir")"
done
if [ -z "$fw_guard" ]; then
	echo "  ℹ 共通基盤が見つからないため第3層の突合はスキップしました（CI の単独チェックアウト等。第2層の検証は上で実施済み）"
elif [ ! -r "$fw_guard" ]; then
	report "共通基盤は見つかりましたが $fw_guard が読めません（第3層が配られていません）"
else
	for entry in "${DUAL_LAYER[@]}"; do
		id="${entry%%:*}"
		grep -qE "^[[:space:]]*#[[:space:]]*@dual-layer:[[:space:]]*${id}([^0-9A-Za-z]|$)" "$fw_guard" \
			|| report "二重化の退化: 共通側のフックに判定 $id のマーカーがありません（第3層が消えています）"
	done
fi

echo "[audit] (6) 必須ステータスチェック宣言の検査..."
# ブランチ保護の設定は GitHub 側にあり、リポジトリからは見えない。設定そのものは機械で検証できないが、
# 「設定できる形になっていること」（宣言した名前が実在し・PR で走り・重複しない）は検証できる。
# 実装は共通側に1本だけ置く（ADR-010: 複製しない）。解決できないときは黙って飛ばさず理由を出す。
rc_dir="$ROOT"
rc_dir_found=""
while [ "$rc_dir" != "/" ]; do
	if [ -f "$rc_dir/.ai-dev-foundation-root" ]; then
		rc_dir_found="$rc_dir"
		break
	fi
	rc_dir="$(dirname "$rc_dir")"
done
rc_script="${rc_dir_found:+$rc_dir_found/common/scripts/check-required-checks.sh}"
if [ -z "$rc_dir_found" ]; then
	echo "  ℹ 共通基盤が見つからないため必須チェック宣言の検査はスキップしました（CI の単独チェックアウト等）"
elif [ ! -r "$rc_script" ]; then
	report "共通基盤は見つかりましたが $rc_script が読めません（共通ゲートが配られていません）"
else
	bash "$rc_script" "$ROOT" || fail=1
fi

echo "[audit] (7) 共通基盤の ref 二重記述の一致検査..."
# reusable workflow を `uses: ...@X` で呼ぶなら `foundation-ref: X` を同じ値で渡す。
# 未指定・不一致だと**別の版の共通基盤でゲートが回る**のに緑になる（症状が出ない）。
fr_script="${rc_dir_found:+$rc_dir_found/common/scripts/check-foundation-ref.sh}"
if [ -z "$rc_dir_found" ]; then
	echo "  ℹ 共通基盤が見つからないため ref 一致の検査はスキップしました（同上）"
elif [ ! -r "$fr_script" ]; then
	report "共通基盤は見つかりましたが $fr_script が読めません（共通ゲートが配られていません）"
else
	bash "$fr_script" "$ROOT" || fail=1
fi

echo "[audit] (8) git フックが作動する状態にあること..."
# 絶対リンクで張られたフックは、張った環境の外では解決できない。**git は解決できない
# シンボリックリンクを「フックが無い」と同じに扱う**ため、警告も出さずに素通りする。
# 2026-08-07 に実際に起きた（devcontainer 内で張り、ホストから push して発覚）。
# 存在・解決・実行権限だけを見る検査では、監査を走らせる環境では常に緑になり何も捕まらない。
gh_script="${rc_dir_found:+$rc_dir_found/common/scripts/check-git-hooks.sh}"
if [ -z "$rc_dir_found" ]; then
	echo "  ℹ 共通基盤が見つからないため git フックの検査はスキップしました（同上）"
elif [ ! -r "$gh_script" ]; then
	report "共通基盤は見つかりましたが $gh_script が読めません（共通ゲートが配られていません）"
else
	bash "$gh_script" "$ROOT" || fail=1
fi

echo ""
if [ "$fail" -ne 0 ]; then
	echo "[audit] ❌ 整合性監査で問題を検出しました。"
	exit 1
fi
echo "[audit] ✅ 整合性監査に問題はありません。"
