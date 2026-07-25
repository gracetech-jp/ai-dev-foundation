#!/usr/bin/env bats
# guard-dangerous.sh（PreToolUse フック）の決定論的遮断を検証する基盤の dogfood テスト。
# permissions.deny の文字列一致をすり抜ける表記ゆれ（結合フラグ・順序違い・パス先行）と、
# bash 経由の秘密ファイル読み取りが確実に deny されることを固定資産として担保する。
#
# 要件トレーサビリティ・マーカー（マーカー規約: docs/rules/testing.md）。
# 破壊的コマンドの表記ゆれ・チェイン実行・秘密読取を試みる adversarial ケースを含むため
# adversarial マーカーも付す。
# @req: R-001
# @adversarial: R-001
# @req: R-002
# @adversarial: R-002

GUARD="${BATS_TEST_DIRNAME}/../.claude/scripts/guard-dangerous.sh"

# Bash コマンド文字列を PreToolUse フック入力(JSON)に包んで guard へ流し込む。
run_guard() {
	jq -n --arg c "$1" '{tool_name:"Bash",tool_input:{command:$c}}' | bash "$GUARD"
}

# サービスリポ想定で guard を実行する（プロジェクトルート＝profiles/_base の無い一時ディレクトリ。
# R-002: 共通所有ファイルのサービス側編集封鎖は基盤リポ以外でのみ有効になる）。
run_guard_svc() {
	jq -n --arg c "$1" '{tool_name:"Bash",tool_input:{command:$c}}' | CLAUDE_PROJECT_DIR="$BATS_TEST_TMPDIR" bash "$GUARD"
}

# 基盤リポ想定で guard を実行する（プロジェクトルート＝profiles/_base を持つこのリポ）。
run_guard_foundation() {
	jq -n --arg c "$1" '{tool_name:"Bash",tool_input:{command:$c}}' | CLAUDE_PROJECT_DIR="$BATS_TEST_DIRNAME/.." bash "$GUARD"
}

# deny 判定を取り出す（許可時は空文字）。jq の整形ゆれ・空入力に頑健。
decision_of() {
	printf '%s' "$1" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null || true
}

# ---- 破壊的コマンドは deny ----

@test "rm -rf を deny する" {
	run run_guard "rm -rf /tmp/x"
	[ "$status" -eq 0 ]
	[ "$(decision_of "$output")" = "deny" ]
}

@test "rm -fr（結合逆順）を deny する" {
	run run_guard "rm -fr /tmp/x"
	[ "$status" -eq 0 ]
	[ "$(decision_of "$output")" = "deny" ]
}

@test "rm dir -rf（パス先行）を deny する" {
	run run_guard "rm /tmp/x -rf"
	[ "$status" -eq 0 ]
	[ "$(decision_of "$output")" = "deny" ]
}

@test "git push --force を deny する" {
	run run_guard "git push --force origin main"
	[ "$status" -eq 0 ]
	[ "$(decision_of "$output")" = "deny" ]
}

@test "git reset --hard を deny する" {
	run run_guard "git reset --hard HEAD~1"
	[ "$status" -eq 0 ]
	[ "$(decision_of "$output")" = "deny" ]
}

@test "git clean -fd を deny する" {
	run run_guard "git clean -fd"
	[ "$status" -eq 0 ]
	[ "$(decision_of "$output")" = "deny" ]
}

@test "git branch -D を deny する" {
	run run_guard "git branch -D feature/x"
	[ "$status" -eq 0 ]
	[ "$(decision_of "$output")" = "deny" ]
}

# ---- 秘密ファイルの bash 経由読み取りは deny ----

@test "cat .env を deny する" {
	run run_guard "cat .env"
	[ "$status" -eq 0 ]
	[ "$(decision_of "$output")" = "deny" ]
}

@test "連結（&& 跨ぎ）でも rm -rf を deny する" {
	run run_guard "echo ok && rm -rf /tmp/x"
	[ "$status" -eq 0 ]
	[ "$(decision_of "$output")" = "deny" ]
}

# ---- 正当な操作は素通し（deny しない = 出力なし） ----

@test "cat .env.example は許可する（サニタイズ対象）" {
	run run_guard "cat .env.example"
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

@test "ls -la は許可する" {
	run run_guard "ls -la"
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

@test "Bash 以外のツールは素通しする" {
	run bash -c 'jq -n "{tool_name:\"Read\",tool_input:{file_path:\".env\"}}" | bash "'"$GUARD"'"'
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

# ---- R-002: 共通所有ファイルのサービス側編集封鎖（ADR-009。基盤リポでは無効） ----

@test "R-002: サービス想定で docs/rules/ へのリダイレクト書込を deny する" {
	run run_guard_svc "echo hack > docs/rules/git.md"
	[ "$status" -eq 0 ]
	[ "$(decision_of "$output")" = "deny" ]
}

@test "R-002: サービス想定でチェイン末尾の追記（>>）も deny する" {
	run run_guard_svc "ls && echo hack >> docs/rules/security.md"
	[ "$status" -eq 0 ]
	[ "$(decision_of "$output")" = "deny" ]
}

@test "R-002: サービス想定で >| による上書き（noclobber 無効化）も deny する" {
	run run_guard_svc "echo hack >| docs/rules/git.md"
	[ "$status" -eq 0 ]
	[ "$(decision_of "$output")" = "deny" ]
}

@test "R-002: サービス想定で >| がチェイン途中にあっても deny する" {
	run run_guard_svc "ls && cat /tmp/x >| CLAUDE.md"
	[ "$status" -eq 0 ]
	[ "$(decision_of "$output")" = "deny" ]
}

@test "R-002: サービス想定で CLAUDE.md への sed -i を deny する" {
	run run_guard_svc "sed -i 's/a/b/' CLAUDE.md"
	[ "$status" -eq 0 ]
	[ "$(decision_of "$output")" = "deny" ]
}

@test "R-002: サービス想定で共通スクリプトへの cp 上書きを deny する" {
	run run_guard_svc "cp /tmp/x scripts/pre-push"
	[ "$status" -eq 0 ]
	[ "$(decision_of "$output")" = "deny" ]
}

@test "R-002: サービス想定で settings.json への tee を deny する" {
	run run_guard_svc "cat /tmp/x | tee .claude/settings.json"
	[ "$status" -eq 0 ]
	[ "$(decision_of "$output")" = "deny" ]
}

@test "R-002: サービス想定で配布スキルへの書込を deny する" {
	run run_guard_svc "echo x > .claude/skills/extract-requirements/SKILL.md"
	[ "$status" -eq 0 ]
	[ "$(decision_of "$output")" = "deny" ]
}

@test "R-002: サービス想定でも共通所有ファイルの読取（cat）は許可する" {
	run run_guard_svc "cat docs/rules/git.md"
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

@test "R-002: サービス想定でも順輸入の実行は許可する（唯一の正規更新経路）" {
	run run_guard_svc "bash scripts/sync-from-common.sh /path/to/common --apply"
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

@test "R-002: 基盤リポ想定では共通所有ファイルの編集を素通しする（編集元）" {
	run run_guard_foundation "sed -i 's/a/b/' CLAUDE.md"
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

@test "R-002: サービス想定で編集前提のファイル（SERVICE.md・Makefile）は素通しする（例外）" {
	run run_guard_svc "echo impl >> Makefile && sed -i 's/a/b/' SERVICE.md"
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

@test "R-002: サービス想定で profiles/_base を元にした骨格同期の cp は許可する（正規手順）" {
	run run_guard_svc "cp ~/projects/ai-dev-foundation/profiles/_base/.claude/scripts/guard-dangerous.sh .claude/scripts/guard-dangerous.sh"
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

@test "R-002: 骨格同期の例外は rsync でも効く" {
	run run_guard_svc "rsync -a ../ai-dev-foundation/profiles/_base/.claude/skills/verify-request/ .claude/skills/verify-request/"
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

@test "R-002: 末尾コメントに profiles/_base を足しても例外は成立せず deny する" {
	run run_guard_svc "cp /tmp/evil .claude/settings.json # profiles/_base/.claude/settings.json"
	[ "$status" -eq 0 ]
	[ "$(decision_of "$output")" = "deny" ]
}

@test "R-002: 骨格同期の例外があってもリダイレクト書込は deny する" {
	run run_guard_svc "cp ../ai-dev-foundation/profiles/_base/CLAUDE.md CLAUDE.md && echo x > docs/rules/git.md"
	[ "$status" -eq 0 ]
	[ "$(decision_of "$output")" = "deny" ]
}

@test "R-002: 骨格同期セグメントがあってもチェイン内の別の cp は deny する" {
	run run_guard_svc "cp ../ai-dev-foundation/profiles/_base/CLAUDE.md CLAUDE.md && cp /tmp/evil scripts/pre-push"
	[ "$status" -eq 0 ]
	[ "$(decision_of "$output")" = "deny" ]
}

@test "R-002: コピー先に profiles/_base を書いても例外は成立せず deny する" {
	run run_guard_svc "cp /tmp/evil scripts/pre-push profiles/_base/"
	[ "$status" -eq 0 ]
	[ "$(decision_of "$output")" = "deny" ]
}

@test "R-002: サービス想定で共通所有ファイルの rm 削除を deny する（申し送り: 編集より影響が大きい）" {
	run run_guard_svc "rm CLAUDE.md"
	[ "$status" -eq 0 ]
	[ "$(decision_of "$output")" = "deny" ]
}

@test "R-002: サービス想定で共通スクリプトの rm 削除も deny する" {
	run run_guard_svc "rm -v scripts/check-tier-tripwire.sh"
	[ "$status" -eq 0 ]
	[ "$(decision_of "$output")" = "deny" ]
}

@test "R-002: 共通所有ファイルに触れないセグメントの rm は素通しする（誤検知しない）" {
	run run_guard_svc "rm build/tmp.txt && cat docs/rules/git.md"
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}
