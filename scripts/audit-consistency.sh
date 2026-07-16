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
# 基盤リポでは配布元 templates/docs/service-rules/ に存在すれば全サービスで解決する。
# どちらにも無ければ全サービスでリンク切れになるため fail とする。
refs_sr=$(grep -rhoE 'docs/service-rules/[a-z0-9-]+\.md' CLAUDE.md docs/ 2>/dev/null | sort -u)
for ref in $refs_sr; do
	if [ ! -f "$ROOT/$ref" ] && [ ! -f "$ROOT/templates/$ref" ]; then
		report "参照先が存在しない: $ref（root にも templates/ にも無し。全サービスでリンク切れになる）"
	fi
done

echo "[audit] (2) make ターゲット契約の検査..."
# quality-gates.md が要求する必須ターゲットが Makefile に定義されているか。
if [ ! -f "$ROOT/Makefile" ]; then
	report "Makefile が存在しない（quality-gates.md が make ターゲットを前提にしている）"
else
	for target in test lint coverage audit-all audit-deps install-hooks; do
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
	scripts/backport-to-common.sh scripts/sync-from-common.sh .backport-manifest COMMAND.md \
	templates/Makefile templates/.github/workflows/ci.yml templates/.editorconfig templates/.coverage-floor \
	templates/.claude/settings.json templates/.claude/scripts/guard-dangerous.sh \
	templates/.claude/scripts/session-start-rules.sh templates/.claude/skills templates/.claude/agents \
	templates/.devcontainer/Dockerfile templates/.devcontainer/postCreate.sh templates/.devcontainer/devcontainer.json \
	templates/gitignore.template templates/.env.example \
	templates/SERVICE.md.template templates/README.md.template \
	templates/docs/service-rules templates/docs/decisions; do
	base="$(basename "$req")"
	if ! grep -q "$base" "$NS"; then
		report "new-service.sh が $base を新サービスへ配布していない（配布漏れ）"
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
# guard-dangerous.sh は jq に依存する。root と templates の Dockerfile は別実体で手動同期のため、
# 片方だけ jq 導入が抜ける「サイレント退化」を検出する（全文一致は強制しない＝意図的分岐は許容）。
for df in .devcontainer/Dockerfile templates/.devcontainer/Dockerfile; do
	if [ ! -f "$ROOT/$df" ]; then
		report "$df が存在しない（devcontainer 設定）"
	elif ! grep -qE '(^|[[:space:]])jq([[:space:]]|$|\\)' "$ROOT/$df"; then
		report "$df が jq を導入していない（guard-dangerous.sh の依存。片側の退化の疑い）"
	fi
done

echo "[audit] (6) 要件パスのブランチ保護確認（要件のLLM編集封鎖の主防壁。docs/rules/git.md）..."
# CODEOWNERS の存在と docs/requirements/ 所有者は必須（ファイル欠落は fail）。
if [ ! -f "$ROOT/.github/CODEOWNERS" ]; then
	report ".github/CODEOWNERS がありません（要件パスのレビュー必須化。docs/rules/git.md）"
elif ! grep -q 'docs/requirements/' "$ROOT/.github/CODEOWNERS"; then
	report ".github/CODEOWNERS に docs/requirements/ の所有者がありません（要件パスが未保護）"
fi
# サーバ側ブランチ保護は GitHub API で確認（不可環境＝CI/未認証はスキップ＋警告。fail にはしない）。
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
	repo="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)"
	if [ -n "$repo" ] && [ "$(gh api "repos/$repo/rulesets" --jq 'length' 2>/dev/null || echo 0)" -gt 0 ]; then
		echo "  ℹ Ruleset を検出。docs/requirements/** に CODEOWNERS レビュー必須が含まれるか手動確認してください。"
	else
		echo "  ⚠ Ruleset/branch protection を API で確認できません。docs/rules/git.md の手動チェックリストで要件パスを保護してください。"
	fi
else
	echo "  ⚠ gh CLI 未認証のためブランチ保護 API 確認をスキップ（CI/ローカルでは想定内）。docs/rules/git.md の手動チェックリストで担保。"
fi

echo ""
if [ "$fail" -ne 0 ]; then
	echo "[audit] ❌ 整合性監査で問題を検出しました。"
	exit 1
fi
echo "[audit] ✅ 整合性監査に問題はありません。"
