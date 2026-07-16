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

GUARD="${BATS_TEST_DIRNAME}/../.claude/scripts/guard-dangerous.sh"

# Bash コマンド文字列を PreToolUse フック入力(JSON)に包んで guard へ流し込む。
run_guard() {
	jq -n --arg c "$1" '{tool_name:"Bash",tool_input:{command:$c}}' | bash "$GUARD"
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
