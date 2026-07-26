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

# ---- 層A: process.env / import.meta.env は「言語構文」であり .env ファイルではない ----
# 秘密パス正規表現 `\.env(\.[a-zA-Z0-9_]+)*` が process.env.NODE_ENV に一致してしまう問題の回帰テスト。
# 層B（READERS へのインタプリタ追加）はこのサニタイズが効いていることを前提に成立する。

@test "層A: grep -r process.env src/ を許可する" {
	run run_guard "grep -r process.env src/"
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

@test "層A: grep -rn process.env.NODE_ENV を許可する" {
	run run_guard "grep -rn 'process.env.NODE_ENV' src/"
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

@test "層A: import.meta.env の grep を許可する" {
	run run_guard "grep -r import.meta.env src/"
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

# ============================================================================
# 層B: インタプリタ経由の秘密ファイル読み取りは deny（2026-07-25）
# サービス側 devcontainer への python / node 導入で「インタプリタが存在しない」前提が消えたため、
# 平文で秘密パスが現れる読み取りを塞ぐ。防御ラインの範囲は docs/rules/security.md §静的検査の防御ライン。
# ============================================================================

@test "層B: python -c による .env 読み取りを deny する" {
	run run_guard "python -c \"print(open('.env').read())\""
	[ "$status" -eq 0 ]
	[ "$(decision_of "$output")" = "deny" ]
}

@test "層B: python3 -c による .env 読み取りを deny する" {
	run run_guard "python3 -c \"import os;print(open('.env').read())\""
	[ "$status" -eq 0 ]
	[ "$(decision_of "$output")" = "deny" ]
}

@test "層B: python -m json.tool .env を deny する" {
	run run_guard "python -m json.tool .env"
	[ "$status" -eq 0 ]
	[ "$(decision_of "$output")" = "deny" ]
}

@test "層B: パイプでコードを流し込む python を deny する" {
	run run_guard "echo \"print(open('.env').read())\" | python"
	[ "$status" -eq 0 ]
	[ "$(decision_of "$output")" = "deny" ]
}

@test "層B: ヒアドキュメント（python3 - <<PY）を deny する" {
	run run_guard "$(printf 'python3 - <<PY\nprint(open(".env").read())\nPY\n')"
	[ "$status" -eq 0 ]
	[ "$(decision_of "$output")" = "deny" ]
}

@test "層B: ヒアドキュメント（node <<JS）を deny する" {
	run run_guard "$(printf 'node <<JS\nconsole.log(require("fs").readFileSync(".env","utf8"))\nJS\n')"
	[ "$status" -eq 0 ]
	[ "$(decision_of "$output")" = "deny" ]
}

@test "層B: node -e による .env 読み取りを deny する" {
	run run_guard "node -e \"console.log(require('fs').readFileSync('.env','utf8'))\""
	[ "$status" -eq 0 ]
	[ "$(decision_of "$output")" = "deny" ]
}

@test "層B: node -p による .env 読み取りを deny する" {
	run run_guard "node -p \"require('fs').readFileSync('.env').toString()\""
	[ "$status" -eq 0 ]
	[ "$(decision_of "$output")" = "deny" ]
}

@test "層B: node --eval による .env 読み取りを deny する" {
	run run_guard "node --eval \"process.stdout.write(require('fs').readFileSync('.env','utf8'))\""
	[ "$status" -eq 0 ]
	[ "$(decision_of "$output")" = "deny" ]
}

@test "層B: node -e による秘密鍵（.ssh/id_rsa）読み取りを deny する" {
	run run_guard "node -e 'console.log(require(\"fs\").readFileSync(process.env.HOME+\"/.ssh/id_rsa\",\"utf8\"))'"
	[ "$status" -eq 0 ]
	[ "$(decision_of "$output")" = "deny" ]
}

@test "層B: perl -ne による .env 読み取りを deny する" {
	run run_guard "perl -ne 'print' .env"
	[ "$status" -eq 0 ]
	[ "$(decision_of "$output")" = "deny" ]
}

@test "層B: perl -0777 -e による .env 読み取りを deny する" {
	run run_guard "perl -0777 -e 'print <>' .env"
	[ "$status" -eq 0 ]
	[ "$(decision_of "$output")" = "deny" ]
}

@test "層B: ruby -e による .env 読み取りを deny する" {
	run run_guard "ruby -e 'puts File.read(\".env\")'"
	[ "$status" -eq 0 ]
	[ "$(decision_of "$output")" = "deny" ]
}

@test "層B: 変数プレフィックス（F=.env）でも deny する" {
	run run_guard "F=.env; python -c \"import os;print(open(os.environ['F']).read())\""
	[ "$status" -eq 0 ]
	[ "$(decision_of "$output")" = "deny" ]
}

@test "層B: pathlib 経由の .env 読み取りを deny する" {
	run run_guard "python -c \"import pathlib;print(pathlib.Path('.env').read_text())\""
	[ "$status" -eq 0 ]
	[ "$(decision_of "$output")" = "deny" ]
}

@test "層B: shutil 経由の .env 読み取りを deny する" {
	run run_guard "python -c \"import shutil,sys;shutil.copyfileobj(open('.env'),sys.stdout)\""
	[ "$status" -eq 0 ]
	[ "$(decision_of "$output")" = "deny" ]
}

@test "層B: 結果をリダイレクト退避しても deny する" {
	run run_guard "python -c \"print(open('.env').read())\" > /tmp/leak"
	[ "$status" -eq 0 ]
	[ "$(decision_of "$output")" = "deny" ]
}

@test "層B: python -c から AWS 認証情報を読むのを deny する" {
	run run_guard "python -c \"print(open('/home/node/.aws/credentials').read())\""
	[ "$status" -eq 0 ]
	[ "$(decision_of "$output")" = "deny" ]
}

@test "層B: python -c から id_rsa を読むのを deny する" {
	run run_guard "python -c \"print(open('id_rsa').read())\""
	[ "$status" -eq 0 ]
	[ "$(decision_of "$output")" = "deny" ]
}

@test "層B: python -c から .pem を読むのを deny する" {
	run run_guard "python -c \"print(open('server.pem').read())\""
	[ "$status" -eq 0 ]
	[ "$(decision_of "$output")" = "deny" ]
}

@test "層B: node -e から .npmrc を読むのを deny する" {
	run run_guard "node -e \"console.log(require('fs').readFileSync('.npmrc','utf8'))\""
	[ "$status" -eq 0 ]
	[ "$(decision_of "$output")" = "deny" ]
}

@test "層B: os.system('cat .env') の間接実行を deny する" {
	run run_guard "python -c \"import os;os.system('cat .env')\""
	[ "$status" -eq 0 ]
	[ "$(decision_of "$output")" = "deny" ]
}

@test "層B: 一時ファイル生成→実行の2段構えも同一コマンドなら deny する" {
	run run_guard "printf 'print(open(\".env\").read())' > /tmp/x.py; python /tmp/x.py"
	[ "$status" -eq 0 ]
	[ "$(decision_of "$output")" = "deny" ]
}

# ---- 層B: 正当な python / node コマンドは素通しする（過剰ブロックの回帰テスト） ----
# ここが壊れると開発が止まる。層A（process.env サニタイズ）が効いていることの担保でもある。

@test "層B許可: node -e で process.env.NODE_ENV を読む" {
	run run_guard "node -e \"console.log(process.env.NODE_ENV)\""
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

@test "層B許可: node -p で process.env.PORT を読む" {
	run run_guard "node -p \"process.env.PORT\""
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

@test "層B許可: npm test" {
	run run_guard "npm test"
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

@test "層B許可: npx tsc --noEmit" {
	run run_guard "npx tsc --noEmit"
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

@test "層B許可: python -m pytest tests/" {
	run run_guard "python -m pytest tests/"
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

@test "層B許可: python manage.py migrate" {
	run run_guard "python manage.py migrate"
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

@test "層B許可: node scripts/build.js" {
	run run_guard "node scripts/build.js"
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

@test "層B許可: os.environ を読む python ワンライナー" {
	run run_guard "python -c \"import os;print(os.environ['PATH'])\""
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

@test "層B許可: python -c の短い計算ワンライナー" {
	run run_guard "python -c \"print(1+1)\""
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

@test "層B許可: node -e で package.json を読む" {
	run run_guard "node -e \"console.log(require('./package.json').version)\""
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

# ============================================================================
# review 指摘の是正（2026-07-25）
#
# 根本原因: READERS のインタプリタ一覧と、#7 のサニタイズ一覧・#8 のパス判定が
# **別々に育つ構造**になっており、片方だけ増やすと誤遮断か穴になる。
# 以下は「インタプリタを足したことで正当なコードが誤遮断された」ケースの回帰テスト。
# ============================================================================

# ---- P1-a: .key/.pem/.p12/.pfx はプロパティアクセスと字面が同じ ----

@test "P1-a: node -e の row.key（プロパティアクセス）を許可する" {
	run run_guard "node -e \"console.log(row.key)\""
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

@test "P1-a: node -e の require('./pkg.json').key を許可する" {
	run run_guard "node -e \"console.log(require('./pkg.json').key)\""
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

@test "P1-a: python3 -c の rec.key を許可する" {
	run run_guard "python3 -c \"print(rec.key)\""
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

@test "P1-a: python -c の obj.pfx を許可する" {
	run run_guard "python -c \"print(obj.pfx)\""
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

@test "P1-a: node -e の o.p12 を許可する" {
	run run_guard "node -e \"console.log(o.p12)\""
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

@test "P1-a: セミコロンが続く m.key も許可する" {
	run run_guard "node -e \"const key = m.key; console.log(key)\""
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

# ---- P1-a: 実ファイルとしての鍵は引き続き deny（緩めすぎていないことの担保） ----

@test "P1-a回帰: cat server.key（行末）を deny する" {
	run run_guard "cat server.key"
	[ "$status" -eq 0 ]
	[ "$(decision_of "$output")" = "deny" ]
}

@test "P1-a回帰: cp certs/server.pem（空白が続く）を deny する" {
	run run_guard "cp certs/server.pem /tmp/"
	[ "$status" -eq 0 ]
	[ "$(decision_of "$output")" = "deny" ]
}

@test "P1-a回帰: head client.p12 を deny する" {
	run run_guard "head -5 client.p12"
	[ "$status" -eq 0 ]
	[ "$(decision_of "$output")" = "deny" ]
}

@test "P1-a回帰: python -c の open('server.key')（引用符が続く）を deny する" {
	run run_guard "python -c \"print(open('server.key').read())\""
	[ "$status" -eq 0 ]
	[ "$(decision_of "$output")" = "deny" ]
}

@test "P1-a回帰: node -e の readFileSync('certs/a.pem') を deny する" {
	run run_guard "node -e \"console.log(require('fs').readFileSync('certs/a.pem','utf8'))\""
	[ "$status" -eq 0 ]
	[ "$(decision_of "$output")" = "deny" ]
}

# ---- P1-b: Bun.env / Deno.env は環境変数構文であってファイルではない ----

@test "P1-b: bun -e の Bun.env.PORT を許可する" {
	run run_guard "bun -e \"console.log(Bun.env.PORT)\""
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

@test "P1-b: deno eval の Deno.env.get('PORT') を許可する" {
	run run_guard "deno eval \"console.log(Deno.env.get('PORT'))\""
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

# ---- P2-b: TypeScript ランナー（ts-node は前方境界が - を除くため node に当たらない） ----

@test "P2-b: tsx -e による .env 読み取りを deny する" {
	run run_guard "tsx -e \"console.log(require('fs').readFileSync('.env','utf8'))\""
	[ "$status" -eq 0 ]
	[ "$(decision_of "$output")" = "deny" ]
}

@test "P2-b: ts-node -e による .env 読み取りを deny する" {
	run run_guard "ts-node -e \"require('fs').readFileSync('.env')\""
	[ "$status" -eq 0 ]
	[ "$(decision_of "$output")" = "deny" ]
}

# ---- 層B×ラッパ: インラインペイロードならラッパ経由でも捕捉される ----

@test "層B: uv run のインラインペイロードは deny する" {
	run run_guard "uv run python -c \"print(open('.env').read())\""
	[ "$status" -eq 0 ]
	[ "$(decision_of "$output")" = "deny" ]
}

@test "層B: poetry run のインラインペイロードは deny する" {
	run run_guard "poetry run python -c \"print(open('.env').read())\""
	[ "$status" -eq 0 ]
	[ "$(decision_of "$output")" = "deny" ]
}

@test "層B: バージョン付き python3.12 -c も deny する" {
	run run_guard "python3.12 -c \"print(open('.env').read())\""
	[ "$status" -eq 0 ]
	[ "$(decision_of "$output")" = "deny" ]
}

# ---- P3: secrets/ の巻き添えは承知のうえの現状維持（挙動を固定する） ----
# 暗号化済み secrets/ を運用するリポジトリでは日常操作が止まる。実運用で阻害されるなら
# 除外を再検討する（判断の記録: docs/rules/security.md §静的検査の防御ライン）。

@test "P3: git diff secrets/ は deny する（巻き添えを承知の fail-safe）" {
	run run_guard "git diff secrets/"
	[ "$status" -eq 0 ]
	[ "$(decision_of "$output")" = "deny" ]
}

@test "P3: grep -rn TODO secrets/ も deny する（同上）" {
	run run_guard "grep -rn TODO secrets/"
	[ "$status" -eq 0 ]
	[ "$(decision_of "$output")" = "deny" ]
}

# ============================================================================
# 層D: 秘密パス辞書の拡充（2026-07-25）
# settings.json の Read deny 側にしか無い / 双方に無いパスが bash 経由で素通ししていた穴。
# インタプリタ問題とは独立。
# ============================================================================

@test "層D: cat secrets/token.txt を deny する" {
	run run_guard "cat secrets/token.txt"
	[ "$status" -eq 0 ]
	[ "$(decision_of "$output")" = "deny" ]
}

@test "層D: ネストした secrets/ ディレクトリも deny する" {
	run run_guard "cat config/secrets/api.yml"
	[ "$status" -eq 0 ]
	[ "$(decision_of "$output")" = "deny" ]
}

@test "層D: head .git-credentials を deny する" {
	run run_guard "head -1 .git-credentials"
	[ "$status" -eq 0 ]
	[ "$(decision_of "$output")" = "deny" ]
}

@test "層D: cat ~/.kube/config を deny する" {
	run run_guard "cat ~/.kube/config"
	[ "$status" -eq 0 ]
	[ "$(decision_of "$output")" = "deny" ]
}

@test "層D: cat ~/.docker/config.json を deny する" {
	run run_guard "cat ~/.docker/config.json"
	[ "$status" -eq 0 ]
	[ "$(decision_of "$output")" = "deny" ]
}

@test "層D: cat ~/.netrc を deny する" {
	run run_guard "cat ~/.netrc"
	[ "$status" -eq 0 ]
	[ "$(decision_of "$output")" = "deny" ]
}

@test "層D: cat ~/.aws/config を deny する（credentials 限定からの拡張）" {
	run run_guard "cat ~/.aws/config"
	[ "$status" -eq 0 ]
	[ "$(decision_of "$output")" = "deny" ]
}

@test "層D: cat ~/.aws/credentials は引き続き deny する（拡張による回帰がない）" {
	run run_guard "cat ~/.aws/credentials"
	[ "$status" -eq 0 ]
	[ "$(decision_of "$output")" = "deny" ]
}

@test "層D: cat id_ecdsa を deny する（bash 側・Read deny と対象を揃えた鍵種）" {
	run run_guard "cat ~/.ssh/id_ecdsa"
	[ "$status" -eq 0 ]
	[ "$(decision_of "$output")" = "deny" ]
}

@test "層D: cat id_dsa を deny する" {
	run run_guard "cat id_dsa"
	[ "$status" -eq 0 ]
	[ "$(decision_of "$output")" = "deny" ]
}

@test "層D: id_rsa.pub（公開鍵）単体は許可する（除去対象・誤検知しない）" {
	run run_guard "cat id_rsa.pub"
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

@test "層D: .ssh/ 配下は .pub でも deny する（ディレクトリ単位の fail-safe。従来からの挙動）" {
	run run_guard "cat ~/.ssh/id_rsa.pub"
	[ "$status" -eq 0 ]
	[ "$(decision_of "$output")" = "deny" ]
}

@test "層D: インタプリタ経由でも secrets/ を deny する（層B×層D）" {
	run run_guard "python -c \"print(open('secrets/token.txt').read())\""
	[ "$status" -eq 0 ]
	[ "$(decision_of "$output")" = "deny" ]
}

# ============================================================================
# 層C: R-002 共通所有ファイルへのインタプリタ経由の変更を deny（2026-07-25）
# 読み取り／書き込みを静的に区別できないため、共起は読み取り目的でも deny（fail-safe）。
# ============================================================================

@test "R-002/層C: node -e の writeFileSync で CLAUDE.md を書き換えるのを deny する" {
	run run_guard_svc "node -e \"require('fs').writeFileSync('CLAUDE.md','x')\""
	[ "$status" -eq 0 ]
	[ "$(decision_of "$output")" = "deny" ]
}

@test "R-002/層C: python -c で docs/rules/ に書き込むのを deny する" {
	run run_guard_svc "python -c \"open('docs/rules/git.md','w').write('x')\""
	[ "$status" -eq 0 ]
	[ "$(decision_of "$output")" = "deny" ]
}

@test "R-002/層C: perl -pi -e による CLAUDE.md の破壊的置換を deny する" {
	run run_guard_svc "perl -pi -e 's/a/b/' CLAUDE.md"
	[ "$status" -eq 0 ]
	[ "$(decision_of "$output")" = "deny" ]
}

@test "R-002/層C: node -e の unlinkSync による CLAUDE.md 削除を deny する" {
	run run_guard_svc "node -e \"require('fs').unlinkSync('CLAUDE.md')\""
	[ "$status" -eq 0 ]
	[ "$(decision_of "$output")" = "deny" ]
}

@test "R-002/層C: 基盤リポ想定ではインタプリタ経由の編集を素通しする（編集元）" {
	run run_guard_foundation "node -e \"require('fs').writeFileSync('CLAUDE.md','x')\""
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

@test "R-002/層C: 共通所有でないファイルへのインタプリタ経由の書込は素通しする" {
	run run_guard_svc "node -e \"require('fs').writeFileSync('README.md','x')\""
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

@test "R-002/層C: サービス側のビルドスクリプト実行は素通しする（誤検知しない）" {
	run run_guard_svc "node scripts/build.js && python -m pytest tests/"
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

# ============================================================================
# 塞げていない抜け道の固定（deny されないことを「仕様」としてテストに書く）
#
# ⚠️ これらは「まだ直していないバグ」ではなく、静的検査では原理的に到達できない範囲である。
#    インタプリタの引数はチューリング完全な言語であり、正規表現でファイル読み取り意図を
#    判定することはできない。将来この節のテストが赤になったら、それは「穴が塞がった」のではなく
#    「別の理由で過剰ブロックが起きた」可能性を先に疑うこと。
#    脅威モデルと防御ラインの根拠: docs/rules/security.md §静的検査の防御ライン
# ============================================================================

@test "既知の限界: 文字列分割（'.e'+'nv'）による難読化は通過する" {
	run run_guard "python -c \"print(open('.e'+'nv').read())\""
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

@test "既知の限界: 配列 join による難読化は通過する" {
	run run_guard "node -e \"console.log(require('fs').readFileSync(['.e','nv'].join('')).toString())\""
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

@test "既知の限界: chr() によるパス生成は通過する" {
	run run_guard "python -c \"print(open(chr(46)+'env').read())\""
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

@test "既知の限界: base64 デコードによるパス生成は通過する" {
	run run_guard "node -e \"console.log(require('fs').readFileSync(Buffer.from('LmVudg==','base64').toString()).toString())\""
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

@test "既知の限界: ファイル実行（python script.py）は通過する（ファイル内容はフックから見えない）" {
	run run_guard "python read_env.py"
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

@test "既知の限界: dotenv ライブラリ経由（パス無記載）は通過する" {
	run run_guard "node -e \"require('dotenv').config();console.log(process.env)\""
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

@test "既知の限界: node -r dotenv/config によるプリロードは通過する" {
	run run_guard "node -r dotenv/config -e \"console.log(process.env)\""
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

@test "既知の限界: npm run 経由の間接実行は通過する（塞ぐと開発が成立しない）" {
	run run_guard "npm run build"
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

# uv run / poetry run は「ラッパだから通る」のではない。インラインペイロード（-c/-e）なら
# コマンド文字列に秘密パスが現れるので捕捉される（下の「層B×ラッパ」テストで固定）。
# 通過するのは **ペイロードが別ファイルにある** 場合だけ。旧テストは `uv run python -c "print(2)"`
# ＝秘密パスを含まない題材だったため、間接実行について何も固定していなかった（2026-07-25 review 指摘）。
# なおこの手のテストは原理上「弱い」: ペイロードが不可視である以上、コマンド文字列だけを見れば
# 素通しは自明である。ここで固定したいのは「ファイル実行は検査対象にならない」という設計事実。
@test "既知の限界: uv run のファイル実行（ペイロードが別ファイル）は通過する" {
	run run_guard "uv run scripts/read_env.py"
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

@test "既知の限界: poetry run のファイル実行は通過する" {
	run run_guard "poetry run python scripts/read_env.py"
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

@test "既知の限界: py（Windows ランチャ）は未列挙のため通過する" {
	run run_guard "py -c \"print(open('.env').read())\""
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

@test "既知の限界: 環境変数経由の漏洩（env | grep）はこのガードの責務外" {
	run run_guard "env | grep -i secret"
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

# ============================================================================
# 誤一致の是正（2026-07-26）— 語が「コマンド」ではなく「パス成分」として現れた場合
#
# 実測で判明した既存の穴。READERS と ADR-009 の変更系コマンド一覧に含まれる語
# （node / python / ruby / perl / deno / bun / php 等）が、パスやディレクトリ名の一部として
# 現れただけで一致し、正当なコマンドを遮断していた。この devcontainer のホームは
# /home/node で、ユーザースコープ配布の実体もそこにあるため、~/ や /home/node/ を含む操作が
# 広範に巻き添えになっていた（14件を実測）。
#
# 是正: 語の直後が `/` `.` `-` のときは一致させない（パス成分・ファイル名と判別する）。
# 先頭側は `/` を許したまま（`/usr/bin/python -c` の絶対パス起動は遮断し続ける）。
# ============================================================================

# ---- 許可: パス成分として現れただけのケース ----

@test "誤一致是正: bash /home/node/.claude/scripts/guard-dangerous.sh を許可する" {
	run run_guard_svc "bash /home/node/.claude/scripts/guard-dangerous.sh"
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

@test "誤一致是正: bash /home/node/.claude/scripts/session-start-rules.sh を許可する" {
	run run_guard_svc "bash /home/node/.claude/scripts/session-start-rules.sh"
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

@test "誤一致是正: ls -la /home/node/ を許可する" {
	run run_guard_svc "ls -la /home/node/"
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

@test "誤一致是正: 共通所有パスを引数に取る diff を許可する（node はパス成分）" {
	run run_guard_svc "diff CLAUDE.md /home/node/.claude/x"
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

@test "誤一致是正: echo で共通所有パスを表示するのを許可する" {
	run run_guard_svc "echo /home/node/.claude/settings.json"
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

@test "誤一致是正: ls -la /home/node/.ssh/ を許可する（ls は読取コマンドではない）" {
	run run_guard "ls -la /home/node/.ssh/"
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

@test "誤一致是正: /home/node/.aws/ を含む文字列の echo を許可する" {
	run run_guard "echo '設定は /home/node/.aws/ にあります'"
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

@test "誤一致是正: stat /home/node/.kube/config を許可する" {
	run run_guard "stat /home/node/.kube/config"
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

@test "誤一致是正: find /usr/lib/python3.12/ を許可する（バージョン付きパス成分）" {
	run run_guard "find /usr/lib/python3.12/ -name '*.pem'"
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

@test "誤一致是正: /opt/ruby/lib/ 配下の ls を許可する" {
	run run_guard "ls /opt/ruby/lib/id_rsa"
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

@test "誤一致是正: /srv/perl/secrets/ の ls を許可する" {
	run run_guard "ls /srv/perl/secrets/"
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

@test "誤一致是正: /opt/deno/secrets/ の ls を許可する" {
	run run_guard "ls /opt/deno/secrets/"
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

@test "誤一致是正: /opt/bun/secrets/ の ls を許可する" {
	run run_guard "ls /opt/bun/secrets/"
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

@test "誤一致是正: /var/php/secrets/ の ls を許可する" {
	run run_guard "ls /var/php/secrets/"
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

@test "誤一致是正: ハイフン付きバージョンディレクトリ /opt/node-14/ を許可する" {
	run run_guard "ls /opt/node-14/bin/id_rsa"
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

# ---- 遮断: 実際のインタプリタ起動は従来どおり（緩めすぎていないことの担保） ----

@test "誤一致是正の回帰: node -e による秘密読取は引き続き deny" {
	run run_guard "node -e \"console.log(require('fs').readFileSync('backend/.env','utf8'))\""
	[ "$status" -eq 0 ]
	[ "$(decision_of "$output")" = "deny" ]
}

@test "誤一致是正の回帰: python -c による秘密読取は引き続き deny" {
	run run_guard "python -c \"print(open('backend/.env').read())\""
	[ "$status" -eq 0 ]
	[ "$(decision_of "$output")" = "deny" ]
}

@test "誤一致是正の回帰: 絶対パス起動 /usr/bin/python -c も引き続き deny" {
	run run_guard "/usr/bin/python -c \"print(open('backend/.env').read())\""
	[ "$status" -eq 0 ]
	[ "$(decision_of "$output")" = "deny" ]
}

@test "誤一致是正の回帰: バージョン付き python3.12 -c も引き続き deny" {
	run run_guard "python3.12 -c \"print(open('backend/.env').read())\""
	[ "$status" -eq 0 ]
	[ "$(decision_of "$output")" = "deny" ]
}

@test "誤一致是正の回帰: deno eval による秘密読取も引き続き deny" {
	run run_guard "deno eval \"console.log(Deno.readTextFileSync('backend/.env'))\""
	[ "$status" -eq 0 ]
	[ "$(decision_of "$output")" = "deny" ]
}

@test "誤一致是正の回帰: node -e による共通所有ファイル書込も引き続き deny" {
	run run_guard_svc "node -e \"require('fs').writeFileSync('CLAUDE.md','x')\""
	[ "$status" -eq 0 ]
	[ "$(decision_of "$output")" = "deny" ]
}

@test "誤一致是正の回帰: ~/.netrc の cat も引き続き deny" {
	run run_guard "cat ~/.netrc"
	[ "$status" -eq 0 ]
	[ "$(decision_of "$output")" = "deny" ]
}
