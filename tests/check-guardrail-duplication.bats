#!/usr/bin/env bats
# common/scripts/check-guardrail-duplication.sh（ガードレール二重化の突合・ADR-012 決定4）の回帰。
#
# この検査は 2026-08-08 に**基盤の audit-consistency.sh (14) と配布雛形の (5) の二重実装**から
# 抽出したものである。抽出で判定が弱まっていないことを、両方の呼ばれ方について固定する。
#
# 基盤とプロジェクトで見る範囲が違う（判別はプロジェクトルートの profiles/_base/ の有無）。
#   基盤    … 配布用 settings.json 群も検証 / 第3層の実体を自分で持つ / 逆方向マーカー検査
#   プロジェクト … 自分の settings.json のみ / 第3層は上方探索 / フック複製とマウントも見る
# **どちらの分岐も抜けが出やすい**ので、両方に赤ケースを置く。
#
# @req: R-001
# @adversarial: R-001

SUT="${BATS_TEST_DIRNAME}/../common/scripts/check-guardrail-duplication.sh"

DUAL_RULES='Bash(git push:*) Bash(git reset *--hard*) Bash(git clean -f*) Bash(git checkout -- *)'
CORE_RULES='Bash(rm -rf:*) Bash(sudo rm:*) Read(**/.env) Read(**/.ssh/**) Read(**/.aws/**)'

# 全ルールを含む settings.json を書く
write_settings() { # <path>
	mkdir -p "$(dirname "$1")"
	{
		printf '{"permissions":{"deny":['
		first=1
		for r in "Bash(git push:*)" "Bash(git reset *--hard*)" "Bash(git clean -f*)" "Bash(git checkout -- *)" \
		         "Bash(rm -rf:*)" "Bash(sudo rm:*)" "Read(**/.env)" "Read(**/.ssh/**)" "Read(**/.aws/**)"; do
			[ "$first" = 1 ] || printf ','
			first=0
			printf '%s' "$(jq -Rn --arg v "$r" '$v')"
		done
		printf ']}}'
	} > "$1"
}

# 4つのマーカーを持つフック本体を書く
write_guard() { # <path>
	mkdir -p "$(dirname "$1")"
	printf '#!/bin/sh\n# @dual-layer: A2\n# @dual-layer: A3\n# @dual-layer: A4\n# @dual-layer: A6\nexit 0\n' > "$1"
}

drop_deny() { # <settings.json> <rule>
	jq --arg r "$2" '.permissions.deny -= [$r]' "$1" > "$1.tmp" && mv "$1.tmp" "$1"
}

setup() {
	F="$BATS_TEST_TMPDIR/foundation"
	# --- 基盤リポの形（profiles/_base/ がある）---
	mkdir -p "$F/profiles/_base/.claude"
	touch "$F/.ai-dev-foundation-root"
	write_settings "$F/.claude/settings.json"
	write_settings "$F/profiles/_base/.claude/settings.json"
	write_guard "$F/.claude/scripts/guard-dangerous.sh"
	# --- プロジェクトの形（基盤の projects/ 配下）---
	P="$F/projects/svc"
	mkdir -p "$P/.devcontainer"
	write_settings "$P/.claude/settings.json"
	printf '{"mounts":["source=x,target=/home/node/.claude,type=bind"]}' > "$P/.devcontainer/devcontainer.json"
}

run_fnd()  { run bash "$SUT" "$F"; }
run_proj() { run bash "$SUT" "$P"; }

# ---- 緑 ----

@test "緑: 基盤リポの正常な構成" {
	run_fnd
	[ "$status" -eq 0 ]
}

@test "緑: プロジェクトの正常な構成" {
	run_proj
	[ "$status" -eq 0 ]
}

# ---- 赤: 第2層（deny）の退化 ----

@test "赤: 基盤の settings.json から二重化 deny を1件落とすと赤" {
	drop_deny "$F/.claude/settings.json" "Bash(git clean -f*)"
	run_fnd
	[ "$status" -eq 1 ]
	[[ "$output" == *"判定 A4"* ]]
}

@test "赤: 基盤は配布用 settings.json の欠落も見る（1本だけ直しても緑にしない）" {
	# ここが抜けると「基盤は直ったが生成プロジェクトはルール無し」になる。
	drop_deny "$F/profiles/_base/.claude/settings.json" "Bash(git push:*)"
	run_fnd
	[ "$status" -eq 1 ]
	[[ "$output" == *"profiles/_base"* ]]
}

@test "赤: deny コアを1件落とすと赤（「1件でもあれば緑」にしない）" {
	drop_deny "$P/.claude/settings.json" "Read(**/.ssh/**)"
	run_proj
	[ "$status" -eq 1 ]
	[[ "$output" == *"deny コアの退化"* ]]
}

@test "赤: settings.json 自体が無いと赤" {
	rm "$P/.claude/settings.json"
	run_proj
	[ "$status" -eq 1 ]
	[[ "$output" == *"第2層の実体"* ]]
}

# ---- 赤: 第3層（フック）の退化 ----

@test "赤: フックから判定マーカーが消えると赤（基盤）" {
	grep -v '@dual-layer: A6' "$F/.claude/scripts/guard-dangerous.sh" > "$F/g" && mv "$F/g" "$F/.claude/scripts/guard-dangerous.sh"
	run_fnd
	[ "$status" -eq 1 ]
	[[ "$output" == *"フックに判定 A6 のマーカーがありません"* ]]
}

@test "赤: フックから判定マーカーが消えると赤（プロジェクトは上方探索で見る）" {
	grep -v '@dual-layer: A3' "$F/.claude/scripts/guard-dangerous.sh" > "$F/g" && mv "$F/g" "$F/.claude/scripts/guard-dangerous.sh"
	run_proj
	[ "$status" -eq 1 ]
	[[ "$output" == *"フックに判定 A3 のマーカーがありません"* ]]
}

@test "赤: 基盤でフック本体が消えると赤（第3層の実体喪失）" {
	rm "$F/.claude/scripts/guard-dangerous.sh"
	run_fnd
	[ "$status" -eq 1 ]
	[[ "$output" == *"第3層の実体"* ]]
}

@test "赤: プロジェクトから見て共通側フックが読めないと赤（配られていない）" {
	rm "$F/.claude/scripts/guard-dangerous.sh"
	run_proj
	[ "$status" -eq 1 ]
	[[ "$output" == *"第3層が配られていません"* ]]
}

@test "赤: 対応表に無いマーカーがフックにあると赤（実装だけ増えて突合が空回りするのを防ぐ）" {
	printf '# @dual-layer: A9\n' >> "$F/.claude/scripts/guard-dangerous.sh"
	run_fnd
	[ "$status" -eq 1 ]
	[[ "$output" == *"突合漏れ"* ]]
}

# ---- 赤: プロジェクト側だけの検査（基盤では対象外であること）----

@test "赤: プロジェクトの settings.json にフック定義があると赤" {
	jq '. + {hooks:{PreToolUse:[{matcher:"Bash"}]}}' "$P/.claude/settings.json" > "$P/t" && mv "$P/t" "$P/.claude/settings.json"
	run_proj
	[ "$status" -eq 1 ]
	[[ "$output" == *"フック定義があります"* ]]
}

@test "緑: 基盤の settings.json にフック定義があるのは正当（対象外）" {
	# ここを分岐し忘れると基盤が永久に赤になる。
	jq '. + {hooks:{PreToolUse:[{matcher:"Bash"}]}}' "$F/.claude/settings.json" > "$F/t" && mv "$F/t" "$F/.claude/settings.json"
	run_fnd
	[ "$status" -eq 0 ]
}

@test "赤: プロジェクトに .claude/scripts の複製が生えると赤" {
	mkdir -p "$P/.claude/scripts"
	printf '#!/bin/sh\n' > "$P/.claude/scripts/guard-dangerous.sh"
	run_proj
	[ "$status" -eq 1 ]
	[[ "$output" == *"フック複製"* ]]
}

@test "緑: 基盤が .claude/scripts を持つのは正当（対象外）" {
	run_fnd
	[ -f "$F/.claude/scripts/guard-dangerous.sh" ]
	[ "$status" -eq 0 ]
}

@test "赤: devcontainer が共通 .claude をマウントしていないと赤" {
	printf '{}' > "$P/.devcontainer/devcontainer.json"
	run_proj
	[ "$status" -eq 1 ]
	[[ "$output" == *"マウントしていません"* ]]
}

@test "緑: compose.yaml 側にマウントがあってもよい" {
	printf '{}' > "$P/.devcontainer/devcontainer.json"
	printf 'services:\n  app:\n    volumes:\n      - ../.claude:/home/node/.claude\n' > "$P/.devcontainer/compose.yaml"
	run_proj
	[ "$status" -eq 0 ]
}

# ---- スキップの可視化 ----

@test "緑: 共通基盤が見つからないときは第3層をスキップし、理由を出す" {
	rm "$F/.ai-dev-foundation-root"
	run_proj
	[ "$status" -eq 0 ]
	[[ "$output" == *"第3層の突合はスキップしました"* ]]
}

# ---- fail-closed ----

@test "exit 2: 引数不足は fail-closed" {
	run bash "$SUT"
	[ "$status" -eq 2 ]
}

@test "exit 2: 存在しないプロジェクトルートは fail-closed" {
	run bash "$SUT" "$F/nope"
	[ "$status" -eq 2 ]
}
