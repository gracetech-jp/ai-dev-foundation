#!/usr/bin/env bash
# 整合性監査 — この基盤リポジトリ自身の整合性を機械的に検証する。
# ドキュメントのリンク切れ・make ターゲット漏れ・リネーム残渣を検出し、
# 問題があれば非ゼロで終了する（pre-push / CI から呼ばれる）。
#
# 枠組みは docs/rules/consistency.md の「監査スクリプトの3層構成」に準拠。
# この基盤リポジトリはアプリコードを持たないため、層(1) grep整合性を中心に実装する。

set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

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

# docs/service-rules/ への参照。CLAUDE.md は共通配布されるため参照先の実体は各サービス側にあり、
# 基盤リポでは配布元 profiles/_base/docs/service-rules/ に存在すれば全サービスで解決する。
# どちらにも無ければ全サービスでリンク切れになるため fail とする。
refs_sr=$(grep -rhoE 'docs/service-rules/[a-z0-9-]+\.md' CLAUDE.md docs/ 2>/dev/null | sort -u)
for ref in $refs_sr; do
	if [ ! -f "$ROOT/$ref" ] && [ ! -f "$ROOT/profiles/_base/$ref" ]; then
		report "参照先が存在しない: $ref（root にも profiles/_base/ にも無し。全サービスでリンク切れになる）"
	fi
done

echo "[audit] (2) make ターゲット契約の検査..."
# quality-gates.md が要求する必須ターゲットが Makefile に定義されているか。
if [ ! -f "$ROOT/Makefile" ]; then
	report "Makefile が存在しない（quality-gates.md が make ターゲットを前提にしている）"
else
	for target in test lint coverage req-coverage tier-tripwire audit-all audit-deps install-hooks; do
		if ! grep -qE "^${target}:" "$ROOT/Makefile"; then
			report "Makefile に必須ターゲット '${target}:' が無い（docs/rules/quality-gates.md 参照）"
		fi
	done
fi

echo "[audit] (3) 新サービスへの配布漏れ検査..."
NS="scripts/new-service.sh"
# new-service.sh が docs/rules 配下を新サービスへ配布しているか。
# 個別 cp のハードコードだと追加ルールの配布漏れが起きるため、ディレクトリ単位の配布を必須とする。
if ! grep -qE 'docs/rules/?"?[^*]*\*|cp -r .*docs/rules|docs/rules/\*' "$NS"; then
	# ディレクトリ一括コピーが見当たらない場合、個別コピーの取りこぼしを検出する。
	for f in docs/rules/*.md; do
		base="$(basename "$f")"
		if ! grep -q "$base" "$NS"; then
			report "new-service.sh が $base を新サービスへ配布していない（配布漏れ）"
		fi
	done
fi
# 品質ゲート・逆輸入プロセス・Claudeガードレール・devcontainer一式が新サービスへ配布されているか
# （配布行の削除・退化を検出）。特に guard-dangerous.sh / settings.json / session-start-rules.sh は
# 安全機構の配布そのものであり、退化すると新サービスがガード無しで生まれるため必ず含める。
# ディレクトリ単位で配布されるもの（skills/agents/service-rules/decisions）は basename がディレクトリ名。
for req in \
	scripts/pre-push scripts/commit-msg scripts/check-coverage.sh scripts/audit-consistency.sh \
	scripts/backport-to-common.sh scripts/sync-from-common.sh .backport-manifest \
	profiles/_base/Makefile profiles/_base/.github/workflows/ci.yml profiles/_base/.editorconfig profiles/_base/.coverage-floor \
	profiles/_base/.claude/settings.json profiles/_base/.claude/scripts/guard-dangerous.sh \
	profiles/_base/.claude/scripts/session-start-rules.sh profiles/_base/.claude/skills profiles/_base/.claude/agents \
	profiles/_base/.devcontainer/Dockerfile profiles/_base/.devcontainer/postCreate.sh profiles/_base/.devcontainer/devcontainer.json \
	profiles/_base/gitignore.template profiles/_base/.env.example \
	profiles/_base/SERVICE.md.template profiles/_base/README.md.template \
	scripts/check-requirements-coverage.sh scripts/check-tier-tripwire.sh \
	profiles/_base/docs/requirements profiles/_base/.github/CODEOWNERS.template \
	profiles/_base/.req-coverage-baseline profiles/_base/.tier-tripwire-allow \
	profiles/_base/docs/service-rules profiles/_base/docs/decisions; do
	base="$(basename "$req")"
	if ! grep -q "$base" "$NS"; then
		report "new-service.sh が $base を新サービスへ配布していない（配布漏れ）"
	fi
done

# 要件トレーサビリティのターゲット/ジョブが配布雛形に存在するか（退化検出）。
for pair in "profiles/_base/Makefile:req-coverage" "profiles/_base/Makefile:tier-tripwire" \
            "profiles/_base/.github/workflows/ci.yml:req-coverage" "profiles/_base/.github/workflows/ci.yml:tier-tripwire"; do
	tfile="${pair%%:*}"; needle="${pair##*:}"
	if [ -f "$ROOT/$tfile" ] && ! grep -q "$needle" "$ROOT/$tfile"; then
		report "$tfile に '$needle' がありません（要件トレーサビリティの配布退化）"
	fi
done

# 基盤リポ自身も CI 多段ゲートを持つ（dogfooding。削除・退化の検出）。
if [ ! -f "$ROOT/.github/workflows/ci.yml" ]; then
	report ".github/workflows/ci.yml が無い（基盤リポ自身のCIゲート。docs/rules/quality-gates.md §4）"
fi

echo "[audit] (4) リネーム残渣スキャン（データ駆動）..."
# 旧名→新名のリネームを行ったら、この配列に "旧名|新名" を1行追加する。
# 旧名がリポジトリ全域に残っていないかを検出する（誤検出回避のため除外パスを絞る）。
renames=(
	# 例: "oldFieldName|newFieldName"
)
# `[@]+...` は空配列+set -u で bash 4.3 以前が unbound エラーになるのを防ぐイディオム
for pair in ${renames[@]+"${renames[@]}"}; do
	old="${pair%%|*}"
	new="${pair##*|}"
	hits=$(grep -rn --exclude-dir=.git --exclude-dir=.claude --exclude="audit-consistency.sh" -- "$old" "$ROOT" 2>/dev/null || true)
	if [ -n "$hits" ]; then
		report "リネーム残渣: 旧名 '$old'（→ '$new'）が残存:"
		# shellcheck disable=SC2001  # 各行への固定プレフィックス付与は sed が最も明瞭
		echo "$hits" | sed 's/^/       /'
	fi
done

echo "[audit] (5) Dockerfile の guard 依存(jq)の二重管理チェック..."
# guard-dangerous.sh は jq に依存する。root と profiles/_base の Dockerfile は別実体で手動同期のため、
# 片方だけ jq 導入が抜ける「サイレント退化」を検出する（全文一致は強制しない＝意図的分岐は許容）。
for df in .devcontainer/Dockerfile profiles/_base/.devcontainer/Dockerfile; do
	if [ ! -f "$ROOT/$df" ]; then
		report "$df が存在しない（devcontainer 設定）"
	elif ! grep -qE '(^|[[:space:]])jq([[:space:]]|$|\\)' "$ROOT/$df"; then
		report "$df が jq を導入していない（guard-dangerous.sh の依存。片側の退化の疑い）"
	fi
done
# プロファイルが Dockerfile を replace する場合、生成サービスの devcontainer はその Dockerfile になる。
# jq を欠くと配布先の guard がサイレントに壊れるため、プロファイル側 Dockerfile も同じ検査に含める（C-8 最小着手）。
for df in "$ROOT"/profiles/*/files/.devcontainer/Dockerfile; do
	[ -f "$df" ] || continue
	rel="${df#"$ROOT"/}"
	if ! grep -qE '(^|[[:space:]])jq([[:space:]]|$|\\)' "$df"; then
		report "$rel が jq を導入していない（guard-dangerous.sh の依存。プロファイル置換による退化）"
	fi
done

echo "[audit] (6) CODEOWNERS 検査（要件パスのレビュー必須化。docs/rules/git.md）..."
# CODEOWNERS の存在と docs/requirements/ 所有者は必須（ファイル欠落は fail）。
if [ ! -f "$ROOT/.github/CODEOWNERS" ]; then
	report ".github/CODEOWNERS がありません（要件パスのレビュー必須化。docs/rules/git.md）"
elif ! grep -q 'docs/requirements/' "$ROOT/.github/CODEOWNERS"; then
	report ".github/CODEOWNERS に docs/requirements/ の所有者がありません（要件パスが未保護）"
fi
# サーバ側ブランチ保護の API 確認は行わない（solo・ブランチ保護未導入の間は認識済みの借金であり、
# 毎push の⚠警告が空回りしていたため 2026-07-23 に撤去）。フェーズ切替（開発者2人以上 or 初回リリース）で
# ブランチ保護を有効化する際、docs/rules/git.md のチェックリストに従い API 確認をここへ再追加する。

echo "[audit] (7) 配布複製の同期検査（root ↔ profiles/_base）..."
# guard-dangerous.sh / session-start-rules.sh / skills / agents は root と profiles/_base の両方に複製配置され、
# 機械還流の対象外＝手動同期（.backport-manifest 注1）。同期漏れは新規サービスだけが古いガードで生まれる
# 「サイレント分岐」になるため、複製ペアの diff 一致を機械強制する（2026-07-22 棚卸しで同期保証の空白として検出）。
while IFS= read -r rel; do
	[ -n "$rel" ] || continue
	if [ ! -f "$ROOT/$rel" ]; then
		report "配布複製の片側欠落: $rel が root 側に無い（profiles/_base のみ存在。手動同期漏れ）"
	elif [ ! -f "$ROOT/profiles/_base/$rel" ]; then
		report "配布複製の片側欠落: $rel が profiles/_base 側に無い（root のみ存在。手動同期漏れ）"
	elif ! diff -q "$ROOT/$rel" "$ROOT/profiles/_base/$rel" >/dev/null 2>&1; then
		report "配布複製が不一致: $rel（root ↔ profiles/_base の手動同期漏れ。diff で差分を確認して揃える）"
	fi
done < <(
	{
		find .claude/scripts .claude/skills .claude/agents -type f 2>/dev/null
		find profiles/_base/.claude/scripts profiles/_base/.claude/skills profiles/_base/.claude/agents -type f 2>/dev/null \
			| sed 's|^profiles/_base/||'
	} | sort -u
)
# settings.json は root にのみローカル固有キー（model/theme/通知フック等）があるため全文一致は課さず、
# 配布の本体である permissions ブロックのみを正規化（キー順・配列内順序を吸収）して比較する。
if command -v jq >/dev/null 2>&1; then
	norm_perms='.permissions | with_entries(.value |= sort)'
	if ! diff -q \
		<(jq -S "$norm_perms" "$ROOT/.claude/settings.json") \
		<(jq -S "$norm_perms" "$ROOT/profiles/_base/.claude/settings.json") >/dev/null 2>&1; then
		report ".claude/settings.json の permissions が root ↔ profiles/_base で不一致（手動同期漏れ）"
	fi
else
	report "jq が無く settings.json の permissions 同期検査ができません（guard-dangerous.sh も jq 依存。導入必須）"
fi

echo ""
if [ "$fail" -ne 0 ]; then
	echo "[audit] ❌ 整合性監査で問題を検出しました。"
	exit 1
fi
echo "[audit] ✅ 整合性監査に問題はありません。"
