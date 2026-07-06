#!/usr/bin/env bash
# 整合性監査 — この基盤リポジトリ自身の整合性を機械的に検証する。
# ドキュメントのリンク切れ・make ターゲット漏れ・リネーム残渣を検出し、
# 問題があれば非ゼロで終了する（pre-push / CI から呼ばれる）。
#
# 枠組みは docs/rules/consistency.md の「監査スクリプトの3層構成」に準拠。
# この基盤リポジトリはアプリコードを持たないため、層(1) grep整合性を中心に実装する。

set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

fail=0
report() {
	# report <メッセージ>
	echo "  ❌ $1"
	fail=1
}

echo "[audit] (1) ドキュメントのリンク切れ検査..."
# CLAUDE.md および docs/rules 配下が参照する docs/rules/*.md が実在するか。
# 'xxx.md' は「詳細: docs/rules/xxx.md」形式の説明用プレースホルダなので除外する。
refs=$(grep -rhoE 'docs/rules/[a-z0-9-]+\.md' CLAUDE.md docs/ 2>/dev/null | sort -u)
for ref in $refs; do
	case "$ref" in
		docs/rules/xxx.md) continue ;;
	esac
	if [ ! -f "$ROOT/$ref" ]; then
		report "参照先が存在しない: $ref（参照元をgrepで確認）"
	fi
done

echo "[audit] (2) make ターゲット契約の検査..."
# quality-gates.md が要求する必須ターゲットが Makefile に定義されているか。
if [ ! -f "$ROOT/Makefile" ]; then
	report "Makefile が存在しない（quality-gates.md が make ターゲットを前提にしている）"
else
	for target in test lint audit-all install-hooks; do
		if ! grep -qE "^${target}:" "$ROOT/Makefile"; then
			report "Makefile に必須ターゲット '${target}:' が無い（docs/rules/quality-gates.md 参照）"
		fi
	done
fi

echo "[audit] (3) 新サービスへのルール配布漏れ検査..."
# new-service.sh が docs/rules 配下を新サービスへ配布しているか。
# 個別 cp のハードコードだと追加ルールの配布漏れが起きるため、ディレクトリ単位の配布を必須とする。
if ! grep -qE 'docs/rules/?"?[^*]*\*|cp -r .*docs/rules|docs/rules/\*' scripts/new-service.sh; then
	# ディレクトリ一括コピーが見当たらない場合、個別コピーの取りこぼしを検出する。
	for f in docs/rules/*.md; do
		base="$(basename "$f")"
		if ! grep -q "$base" scripts/new-service.sh; then
			report "new-service.sh が $base を新サービスへ配布していない（配布漏れ）"
		fi
	done
fi

echo "[audit] (4) リネーム残渣スキャン（データ駆動）..."
# 旧名→新名のリネームを行ったら、この配列に "旧名|新名" を1行追加する。
# 旧名がリポジトリ全域に残っていないかを検出する（誤検出回避のため除外パスを絞る）。
renames=(
	# 例: "oldFieldName|newFieldName"
)
for pair in "${renames[@]}"; do
	old="${pair%%|*}"
	new="${pair##*|}"
	hits=$(grep -rn --exclude-dir=.git --exclude-dir=.claude --exclude="audit-consistency.sh" -- "$old" "$ROOT" 2>/dev/null || true)
	if [ -n "$hits" ]; then
		report "リネーム残渣: 旧名 '$old'（→ '$new'）が残存:"
		echo "$hits" | sed 's/^/       /'
	fi
done

echo ""
if [ "$fail" -ne 0 ]; then
	echo "[audit] ❌ 整合性監査で問題を検出しました。"
	exit 1
fi
echo "[audit] ✅ 整合性監査に問題はありません。"
