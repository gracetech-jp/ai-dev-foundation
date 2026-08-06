#!/usr/bin/env bats
# audit-consistency.sh 検査層(6)「配布複製の同期検査（root ↔ profiles/_base）」の回帰。
# 実リポの working tree を汚さないため、監査対象一式をサンドボックスへ複製してから破壊する。

setup() {
	REPO="$BATS_TEST_DIRNAME/.."
}

# 監査スクリプトが参照する一式を複製する（.claude はローカル設定 settings.local.json を含めない）
make_sandbox() {
	SB="$BATS_TEST_TMPDIR/sb"
	mkdir -p "$SB/.claude" "$SB/docs"
	# common / templates / マーカーは検査層(10)（参照方式への移行中の複製同期検査）の対象。
	# 複製し忘れると層(10)がサンドボックスで必ず落ちる（2026-07-26 フェーズ0で追加）。
	for item in Makefile CLAUDE.md README.md \
	            .req-coverage-baseline scripts profiles .github .devcontainer \
	            common service-templates .ai-dev-foundation-root; do
		cp -a "$REPO/$item" "$SB/$item"
	done
	cp -a "$REPO/docs/rules" "$REPO/docs/requirements" "$REPO/docs/service-rules" "$REPO/docs/decisions" "$SB/docs/"
	cp "$REPO/docs/README.md" "$SB/docs/"   # 検査層(12) 所在の正本（各階層 README）の対象
	cp "$REPO/.claude/settings.json" "$SB/.claude/"
	cp -a "$REPO/.claude/scripts" "$REPO/.claude/skills" "$REPO/.claude/agents" "$SB/.claude/"
}

audit() { (cd "$SB" && bash scripts/audit-consistency.sh); }

# ---- 緑 ----

@test "緑: サンドボックス（現リポの複製）で監査が通る" {
	make_sandbox
	run audit
	[ "$status" -eq 0 ]
}

@test "緑: settings.json は permissions が同値なら root 固有キー（model等）の差を許容する" {
	make_sandbox
	# root 側にのみ存在するローカル固有キーを追加しても層(6)は赤にならない
	jq '. + {theme: "light", model: "dummy"}' "$SB/.claude/settings.json" > "$SB/.claude/settings.json.tmp"
	mv "$SB/.claude/settings.json.tmp" "$SB/.claude/settings.json"
	run audit
	[ "$status" -eq 0 ]
}

# ---- 赤 ----

@test "赤: 配布側にフック複製が再発すると fail する" {
	# 2026-08-04・ADR-012 フェーズ2: フック本体はユーザースコープ1本に集約した。
	# 旧ケース（root ↔ _base の複製が不一致なら赤）は、複製そのものを廃止したため
	# 「複製が再び生えたら赤」へ差し替えた。生えると $CLAUDE_PROJECT_DIR 依存の構成へ逆戻りする。
	make_sandbox
	mkdir -p "$SB/profiles/_base/.claude/scripts"
	cp "$SB/.claude/scripts/guard-dangerous.sh" "$SB/profiles/_base/.claude/scripts/"
	run audit
	[ "$status" -eq 1 ]
	[[ "$output" == *"フック複製が再発しています"* ]]
}

@test "赤: root 側のスキルファイルだけ削除すると片側欠落で fail" {
	make_sandbox
	rm "$SB/.claude/skills/verify-request/SKILL.md"
	run audit
	[ "$status" -eq 1 ]
	[[ "$output" == *"配布複製の片側欠落"*"verify-request/SKILL.md"* ]]
}

@test "赤: profiles/_base 側にだけ新規エージェントを置くと片側欠落で fail" {
	make_sandbox
	mkdir -p "$SB/profiles/_base/.claude/agents"
	echo "dummy" > "$SB/profiles/_base/.claude/agents/only-base.md"
	run audit
	[ "$status" -eq 1 ]
	[[ "$output" == *"配布複製の片側欠落"*"only-base.md"*"root 側に無い"* ]]
}

@test "赤: _base 側 settings.json の permissions.deny を1件消すと fail" {
	make_sandbox
	jq '.permissions.deny -= ["Bash(git push:*)"]' "$SB/profiles/_base/.claude/settings.json" \
		> "$SB/profiles/_base/.claude/settings.json.tmp"
	mv "$SB/profiles/_base/.claude/settings.json.tmp" "$SB/profiles/_base/.claude/settings.json"
	run audit
	[ "$status" -eq 1 ]
	[[ "$output" == *"permissions が root ↔ profiles/_base で不一致"* ]]
}

# ---- 検査層(7): 共通所有ロックの定義突合（2026-07-25 追加） ----

@test "赤: guard の COMMON_OWNED に無いパスを deny に足すと乖離で fail" {
	make_sandbox
	jq '.permissions.deny += ["Write(docs/newthing.md)", "Edit(docs/newthing.md)"]' \
		"$SB/profiles/_base/.claude/settings.json" > "$SB/t.json"
	mv "$SB/t.json" "$SB/profiles/_base/.claude/settings.json"
	run audit
	[ "$status" -eq 1 ]
	[[ "$output" == *"共通所有ロックの乖離"*"docs/newthing.md"*"COMMON_OWNED に掛かりません"* ]]
}

# Write(path) はファイル権限チェックに一致せず効かない。Edit(path) が全ファイル編集ツールを覆う。
# 旧テストは Write/Edit の対称性を要求していたが、効かないルールを必須にする検査だった（2026-07-26 是正）。
@test "赤: 効かない Write(...) の deny を配布 settings.json に置くと fail" {
	make_sandbox
	jq '.permissions.deny += ["Write(CLAUDE.md)"]' \
		"$SB/profiles/_base/.claude/settings.json" > "$SB/t.json"
	mv "$SB/t.json" "$SB/profiles/_base/.claude/settings.json"
	run audit
	[ "$status" -eq 1 ]
	[[ "$output" == *"Write(...) の deny が残っています"* ]]
}

@test "赤: ロックのコアから Edit を1件外すと退化検出で fail" {
	make_sandbox
	jq '.permissions.deny |= map(select(. != "Edit(CLAUDE.md)"))' \
		"$SB/profiles/_base/.claude/settings.json" > "$SB/t.json"
	mv "$SB/t.json" "$SB/profiles/_base/.claude/settings.json"
	run audit
	[ "$status" -eq 1 ]
	# 部分文字列ごとに検査する（1つの glob で順に並べると、別の検査が出す
	# 「CLAUDE.md」を含む行に引っ張られて**別の理由で緑になる**ため。2026-07-30）
	[[ "$output" == *"ロックの退化"* ]]
	[[ "$output" == *"Edit(CLAUDE.md)"* ]]
}

# 旧「manifest の配布対象がロックされていないと fail」は 2026-07-30 に撤去した
# （順輸入廃止・ADR-010 でマニフェストが無くなり、検査ごと消えたため）。

@test "赤: ロックのコア1件を deny から外すと退化検出で fail（旧 length>0 では素通りしていた）" {
	make_sandbox
	jq '.permissions.deny |= map(select(. != "Edit(.claude/scripts/session-start-rules.sh)"))' \
		"$SB/profiles/_base/.claude/settings.json" > "$SB/t.json"
	mv "$SB/t.json" "$SB/profiles/_base/.claude/settings.json"
	run audit
	[ "$status" -eq 1 ]
	[[ "$output" == *"ロックの退化"* ]]
	[[ "$output" == *"Edit(.claude/scripts/session-start-rules.sh)"* ]]
}

# ---- 検査層(8): 基盤自身のゲート無効化検出（2026-07-25 追加） ----

@test "赤: 基盤の tier-tripwire を空設定に戻すと無効化検出で fail" {
	make_sandbox
	sed -i "s|@TIER_TRIPWIRE_PATHS='[^']*'|@TIER_TRIPWIRE_PATHS=\"\"|" "$SB/Makefile"
	run audit
	[ "$status" -eq 1 ]
	[[ "$output" == *"TIER_TRIPWIRE_PATHS 空で起動"* ]]
}

@test "赤: 基盤に .tier-tripwire-none を置くと無効化検出で fail" {
	make_sandbox
	: > "$SB/docs/requirements/.tier-tripwire-none"
	run audit
	[ "$status" -eq 1 ]
	[[ "$output" == *".tier-tripwire-none があります"* ]]
}

@test "赤: CI から tier-tripwire の実行が消えると退化検出で fail" {
	make_sandbox
	# ジョブ名ではなく**ゲートの実行**を見る（2026-08-04・ADR-011）。
	# ジョブ名を残したまま中身だけ抜いても検出できることを固定する。
	sed -i 's|^      - run: make tier-tripwire$|      - run: echo skip|' "$SB/.github/workflows/ci.yml"
	run audit
	[ "$status" -eq 1 ]
	[[ "$output" == *"必須ゲート 'tier-tripwire' が実行されていません"* ]]
}

@test "赤: CI から secret-scan（gitleaks）が消えると退化検出で fail" {
	make_sandbox
	grep -v 'gitleaks' "$SB/.github/workflows/ci.yml" > "$SB/ci.tmp"
	mv "$SB/ci.tmp" "$SB/.github/workflows/ci.yml"
	run audit
	[ "$status" -eq 1 ]
	[[ "$output" == *"必須ゲート 'secret-scan' が実行されていません"* ]]
}

@test "緑: reusable workflow 呼び出し形でも必須ゲートを満たしていれば通る" {
	make_sandbox
	# 将来サービス側の CI がこの形になっても検出力が落ちないことを固定する
	# （基盤自身は reusable を呼ばない方針だが、検査は両形を受け付ける）。
	cat > "$SB/.github/workflows/ci.yml" <<-'YAML'
		name: CI
		on: [push, pull_request]
		jobs:
		  ci:
		    uses: gracetech-jp/ai-dev-foundation/.github/workflows/service-ci.yml@v2
		    with:
		      project-name: dummy
		      common-gates: "audit-all req-coverage tier-tripwire"
		      stack-gates: "lint test coverage audit-deps"
		  secret-scan:
		    runs-on: ubuntu-latest
		    steps:
		      - run: docker run --rm ghcr.io/gitleaks/gitleaks:v8.18.4 detect
	YAML
	# CI の形を変えたら必須チェックの宣言も追随する（検査(16)。ここを直さないと赤になるのが正しい）
	printf 'ci / gates\nsecret-scan\n' > "$SB/.github/required-checks.txt"
	run audit
	[ "$status" -eq 0 ]
}

# ---- 赤: 検査層(10) 参照方式への移行中の複製同期（2026-07-26 フェーズ0） ----
# 移行期は正本(common/ ・ service-templates/)と旧パスの実体が併存する。片方だけ育つ乖離を機械で止める。

@test "赤: _base の Dockerfile だけ改変すると複製の不一致で fail" {
	make_sandbox
	echo "# drift" >> "$SB/profiles/_base/.devcontainer/Dockerfile"
	run audit
	[ "$status" -eq 1 ]
	[[ "$output" == *"移行複製が不一致"* ]]
	[[ "$output" == *"Dockerfile"* ]]
}

@test "赤: composite action 同梱スクリプトだけ改変すると移行複製の不一致で fail" {
	make_sandbox
	echo "# drift" >> "$SB/.github/actions/tier-tripwire/check-tier-tripwire.sh"
	run audit
	[ "$status" -eq 1 ]
	[[ "$output" == *"移行複製が不一致"* ]]
}

@test "赤: templates 側だけ改変すると profiles/_base との不一致で fail" {
	make_sandbox
	echo "# drift" >> "$SB/service-templates/scripts/audit-consistency.sh"
	run audit
	[ "$status" -eq 1 ]
	[[ "$output" == *"移行複製が不一致"*"service-templates/"* ]]
}

@test "赤: マーカーを消すと参照方式の起点欠落で fail" {
	make_sandbox
	rm "$SB/.ai-dev-foundation-root"
	run audit
	[ "$status" -eq 1 ]
	[[ "$output" == *"マーカー"* ]]
}

# ---- 赤: 検査層(11) 参照方式の退化検出（2026-07-30 ADR-010） ----
# 共通スクリプトの実体は common/scripts/ のみ。ドキュメント・雛形が複製前提のパスで案内すると
# 読者が存在しないファイルを探すことになる。移行時に実際に取り残しが出たため常設した検査。

@test "赤: docs/rules が共通スクリプトを複製前提のパスで案内すると退化検出で fail" {
	make_sandbox
	echo '判定は `scripts/check-coverage.sh` が行う。' >> "$SB/docs/rules/quality-gates.md"
	run audit
	[ "$status" -eq 1 ]
	[[ "$output" == *"参照方式の退化"* ]]
	[[ "$output" == *"quality-gates.md"* ]]
}

@test "赤: 雛形 PROJECT.md.template が複製前提のパスで案内すると退化検出で fail" {
	make_sandbox
	echo '照合エンジンは `scripts/check-tier-tripwire.sh`。' >> "$SB/profiles/_base/PROJECT.md.template"
	run audit
	[ "$status" -eq 1 ]
	[[ "$output" == *"参照方式の退化"* ]]
	[[ "$output" == *"PROJECT.md.template"* ]]
}

@test "緑: settings.json の deny 表記（複製を作らせないロック）は退化扱いしない" {
	make_sandbox
	# Edit(scripts/pre-push) はバッククォート付きのパス案内ではなくロックの定義。
	# これを退化と誤検出すると、ロックを外す方向へ人を誘導してしまう。
	grep -q 'Edit(scripts/pre-push)' "$SB/profiles/_base/.claude/settings.json"
	run audit
	[ "$status" -eq 0 ]
}

# ---- 赤/緑: 検査層(12) 所在の正本（各階層 README とツリー）（2026-07-30 決定） ----
# 「何がどこにあるか」は各階層の README が正本。README かツリーが欠けると、所在の記述が
# またルール文書側へ散り、構成変更のたびに N 文書を追う羽目になる。

@test "赤: 階層 README が消えると所在の正本欠落で fail" {
	make_sandbox
	rm "$SB/common/README.md"
	run audit
	[ "$status" -eq 1 ]
	[[ "$output" == *"common/README.md がありません"* ]]
}

@test "赤: 階層 README からツリーが消えると fail" {
	make_sandbox
	# ツリーの根の行（`docs/decisions/`）だけを削り、README 自体は残す
	grep -vxF 'docs/decisions/' "$SB/docs/decisions/README.md" > "$SB/t.md"
	mv "$SB/t.md" "$SB/docs/decisions/README.md"
	run audit
	[ "$status" -eq 1 ]
	[[ "$output" == *"自ディレクトリのツリーがありません"* ]]
	[[ "$output" == *"docs/decisions/README.md"* ]]
}

# ---- 赤/緑: 検査層(1) リンク切れと ADR の除外（2026-08-03 決定） ----
# 検査(1) は docs/decisions/（ADR）を走査対象から外している。ADR の「結果」節には
# これから新設するファイルのパスが書かれるため、実在検査をかけると起票のたびに赤になる。
# ただし除外を入れた結果、実リポには壊れた参照が1つも無い＝**検査(1) を壊してもテストが
# 緑のまま通る**状態になった。以下の2ケースで「検査が生きていること」と「除外が効いていること」
# を両側から留める（片側だけだと、検査全体を殺す変更と除外を外す変更のどちらかを見逃す）。

@test "赤: docs/rules が未実在の docs/rules/*.md を参照すると リンク切れ検出で fail" {
	make_sandbox
	# 'xxx.md' はプレースホルダとして明示除外されているため、別名を使う。
	[ ! -f "$SB/docs/rules/not-a-real-rule.md" ]
	echo '詳細: `docs/rules/not-a-real-rule.md`' >> "$SB/docs/rules/testing.md"
	run audit
	[ "$status" -eq 1 ]
	[[ "$output" == *"参照先が存在しない"* ]]
	[[ "$output" == *"docs/rules/not-a-real-rule.md"* ]]
}

# ---- 赤/緑: 検査層(13) 隔離境界の退化検出（2026-08-04・ADR-013） ----
# 境界を成す要素が Dockerfile から落ちても、ビルドは通りコンテナも動く。何も起きないまま
# 防御だけが消えるため、人手のレビューでは捕まらない。特に sudo の無制限化は、
# ファイアウォールを入れていても `sudo iptables -F` で解除できる状態に戻す。

@test "赤: Dockerfile の sudo が NOPASSWD:ALL に戻ると隔離境界の退化で fail" {
	make_sandbox
	# コメントではなく実行される行として戻す（コメント中の言及は誤検出しない設計）
	echo 'RUN echo "node ALL=(root) NOPASSWD:ALL" > /etc/sudoers.d/node' \
		>> "$SB/profiles/_base/.devcontainer/Dockerfile"
	run audit
	[ "$status" -eq 1 ]
	[[ "$output" == *"sudo を無制限に許可"* ]]
}

@test "緑: Dockerfile のコメント中の NOPASSWD:ALL は退化扱いしない" {
	make_sandbox
	grep -q 'NOPASSWD:ALL' "$SB/profiles/_base/.devcontainer/Dockerfile"
	run audit
	[ "$status" -eq 0 ]
}

@test "赤: bypassPermissions のまま MCP の ask を外すと fail" {
	make_sandbox
	# bypass は明示的な ask だけは素通りしないため、mcp__* が MCP に対する唯一の実行時の歯止め
	jq '.permissions.ask -= ["mcp__*"]' "$SB/profiles/_base/.claude/settings.json" > "$SB/t.json"
	mv "$SB/t.json" "$SB/profiles/_base/.claude/settings.json"
	run audit
	[ "$status" -eq 1 ]
	[[ "$output" == *"ask に 'mcp__*' がありません"* ]]
}

@test "赤: compose から cap_add の NET_ADMIN が消えると fail" {
	make_sandbox
	cf="$SB/profiles/product-web/files/.devcontainer/compose.yaml"
	grep -v 'NET_ADMIN' "$cf" > "$SB/t"
	mv "$SB/t" "$cf"
	run audit
	[ "$status" -eq 1 ]
	[[ "$output" == *"cap_add の NET_ADMIN がありません"* ]]
}

@test "赤: プロファイル Dockerfile から init-firewall.sh の COPY が消えると fail" {
	make_sandbox
	df="$SB/profiles/product-web/files/.devcontainer/Dockerfile"
	grep -v 'COPY init-firewall.sh /usr/local/bin/init-firewall.sh' "$df" > "$SB/t"
	mv "$SB/t" "$df"
	run audit
	[ "$status" -eq 1 ]
	[[ "$output" == *"隔離境界の退化"* ]]
	[[ "$output" == *"product-web"* ]]
}

# ---- 赤: ファイアウォール（ADR-013 第1層）の配布と正本一致 ----
# init-firewall.sh は「配られていなければ第1層が存在しない」もの。配布行が消えても、正本と複製が
# 割れても、生成されたプロジェクトは**遮断なしで立ち上がる**。どちらも無言の退化になるため留める。

@test "赤: init-firewall.sh の配布行が消えると配布漏れで fail" {
	make_sandbox
	grep -v 'init-firewall.sh' "$SB/scripts/new-service.sh" > "$SB/t.sh"
	mv "$SB/t.sh" "$SB/scripts/new-service.sh"
	run audit
	[ "$status" -eq 1 ]
	[[ "$output" == *"init-firewall.sh を新サービスへ配布していない"* ]]
}

@test "赤: init-firewall.sh の正本と配布複製が割れると fail" {
	make_sandbox
	echo "# drift" >> "$SB/profiles/_base/.devcontainer/init-firewall.sh"
	run audit
	[ "$status" -eq 1 ]
	[[ "$output" == *"移行複製が不一致"* ]]
	[[ "$output" == *"init-firewall.sh"* ]]
}

# ---- 赤/緑: 検査層(6) permissions 正規化がスカラー値で潰れないこと（2026-08-04・ADR-013） ----
# 検査(6)は permissions を jq で正規化して比較する。旧実装は全キーに無条件 sort を掛けており、
# 配列でない値（`defaultMode` は文字列）が1つ入るだけで jq が異常終了し、diff の**両側が空**に
# なって「差分なし＝緑」と判定された。つまり permissions の同期検査が無言で止まる。
# 「作動していないゲート」を作らないため、スカラー値がある状態で検出能力が残ることを留める。

# permissions.defaultMode を root / _base / プロファイルの3系統すべてに入れる
# （検査(7)が「ask 以外はプロファイルと _base で同値」を課すため、片方だけでは別検査が赤になり
#   検査(6)を素通りさせても気づけないテストになる）
add_default_mode() {
	local f
	for f in "$SB/.claude/settings.json" "$SB/profiles/_base/.claude/settings.json" \
	         "$SB"/profiles/*/files/.claude/settings.json; do
		[ -f "$f" ] || continue
		jq '.permissions.defaultMode = "bypassPermissions"' "$f" > "$SB/t.json"
		mv "$SB/t.json" "$f"
	done
}

@test "緑: permissions に defaultMode（文字列）があっても監査が通る" {
	make_sandbox
	add_default_mode
	run audit
	[ "$status" -eq 0 ]
}

@test "赤: defaultMode があっても permissions の同期検査が生きている（型で潰れない）" {
	make_sandbox
	add_default_mode
	# この状態で _base 側の deny を1件落とす。正規化が壊れていると検出できずに緑になる
	jq '.permissions.deny -= ["Bash(git push:*)"]' "$SB/profiles/_base/.claude/settings.json" > "$SB/t.json"
	mv "$SB/t.json" "$SB/profiles/_base/.claude/settings.json"
	run audit
	[ "$status" -eq 1 ]
	[[ "$output" == *"permissions が root ↔ profiles/_base で不一致"* ]]
}

@test "緑: ADR が未実在の docs/rules/*.md を参照しても リンク切れ扱いしない" {
	make_sandbox
	# 実在の ADR に追記すると、その ADR が消えた時にテストの意味が静かに失われるため、
	# 「結果」節を持つ ADR を模した専用の入力を置く。
	[ ! -f "$SB/docs/rules/not-a-real-rule.md" ]
	cat > "$SB/docs/decisions/099-fixture-for-link-check.md" <<-'EOF'
		# ADR-099: リンク切れ検査の除外を検証するための入力

		## 結果

		- `docs/rules/not-a-real-rule.md` を新設する
	EOF
	run audit
	[ "$status" -eq 0 ]
}

# ---- 赤/緑: 検査層(14) 二重化の突合（2026-08-04・ADR-012 決定4） ----
# 二重化は「片側が消えても何も起きない」形で壊れる（テストは緑のまま、コンテナも動く）。
# 検査そのものが空回りしていないことを、両側の欠落・突合漏れの3方向で固定する。

# サンドボックスの settings.json から deny を1件落とす補助
drop_deny_from() { # <$SB からの相対パス> <ルール文字列>
	jq --arg r "$2" '.permissions.deny -= [$r]' "$SB/$1" > "$SB/t.json"
	mv "$SB/t.json" "$SB/$1"
}

@test "赤: 第3層のマーカーが消えると二重化の退化として fail する" {
	make_sandbox
	# フックから A3 の判定が消えた状況を、マーカーを落として再現する
	grep -v '@dual-layer: A3' "$SB/.claude/scripts/guard-dangerous.sh" > "$SB/g.sh"
	mv "$SB/g.sh" "$SB/.claude/scripts/guard-dangerous.sh"
	run audit
	[ "$status" -eq 1 ]
	[[ "$output" == *"二重化の退化"*"A3"* ]]
}

@test "赤: 第2層の deny が1本から消えると同期漏れとして fail する" {
	make_sandbox
	drop_deny_from "profiles/product-web/files/.claude/settings.json" "Bash(git checkout -- *)"
	run audit
	[ "$status" -eq 1 ]
	[[ "$output" == *"二重化の退化"*"A6"* ]]
}

@test "赤: フックにマーカーがあるのに対応表に無ければ突合漏れとして fail する" {
	make_sandbox
	printf '# @dual-layer: Z9\n' >> "$SB/.claude/scripts/guard-dangerous.sh"
	run audit
	[ "$status" -eq 1 ]
	[[ "$output" == *"二重化の突合漏れ"*"Z9"* ]]
}

@test "赤: deny コアが1本から消えると fail する" {
	make_sandbox
	drop_deny_from ".claude/settings.json" "Read(**/.ssh/**)"
	run audit
	[ "$status" -eq 1 ]
	[[ "$output" == *"deny コアの退化"* ]]
}

@test "赤: 配布 devcontainer から共通 .claude のマウントが消えると fail する" {
	make_sandbox
	# ユーザースコープへのマウントが唯一の配布経路（ADR-012 フェーズ2）。消えると無警告で丸ごと無効になる
	grep -v '/home/node/.claude' "$SB/profiles/_base/.devcontainer/devcontainer.json" > "$SB/d.json"
	mv "$SB/d.json" "$SB/profiles/_base/.devcontainer/devcontainer.json"
	run audit
	[ "$status" -eq 1 ]
	[[ "$output" == *"/home/node/.claude へマウントしていません"* ]]
}

@test "赤: compose 方式のプロファイルでマウントが消えても fail する" {
	make_sandbox
	grep -v '/home/node/.claude' "$SB/profiles/product-web/files/.devcontainer/compose.yaml" > "$SB/c.yaml"
	mv "$SB/c.yaml" "$SB/profiles/product-web/files/.devcontainer/compose.yaml"
	run audit
	[ "$status" -eq 1 ]
	[[ "$output" == *"/home/node/.claude へマウントしていません"* ]]
}

# ---- 赤/緑: 検査層(15) ワークフロー式の文脈検査（2026-08-04・実際に踏んだ失敗の再発防止） ----

@test "赤: step の if: が secrets を参照すると fail する" {
	make_sandbox
	# これを書くとワークフロー全体が Invalid workflow file になり、on: すら評価されずに
	# push で0秒失敗する（2026-08-04 に service-ci.yml で実際に発生した）
	cat > "$SB/.github/workflows/dummy.yml" <<-'YAML'
		name: dummy
		on: [push]
		jobs:
		  x:
		    runs-on: ubuntu-latest
		    steps:
		      - run: echo hi
		        if: secrets.SOME_TOKEN != ''
	YAML
	run audit
	[ "$status" -eq 1 ]
	[[ "$output" == *"ワークフロー式の文脈エラー"* ]]
}

@test "緑: job-level env に落としてから env を見る形は通る（正しい回避形）" {
	make_sandbox
	cat > "$SB/.github/workflows/dummy.yml" <<-'YAML'
		name: dummy
		on: [push]
		jobs:
		  x:
		    runs-on: ubuntu-latest
		    env:
		      HAS_TOKEN: ${{ secrets.SOME_TOKEN != '' }}
		    steps:
		      - run: echo hi
		        if: env.HAS_TOKEN == 'true'
	YAML
	run audit
	[ "$status" -eq 0 ]
}

@test "赤: 必須チェック宣言が消えると検査(16)が fail する（配線されていること）" {
	# 検査の中身は tests/check-required-checks.bats が固定している。ここで見るのは
	# 「監査から実際に呼ばれているか」——呼び出しが外れても他は緑のままなので、単体では気づけない。
	make_sandbox
	rm "$SB/.github/required-checks.txt"
	run audit
	[ "$status" -eq 1 ]
	[[ "$output" == *"required-checks.txt がありません"* ]]
}

@test "赤: 基盤の CI ジョブ名を変えて宣言を直し忘れると fail する" {
	make_sandbox
	sed -i 's/^  tier-tripwire:/  tier-tripwire-renamed:/' "$SB/.github/workflows/ci.yml"
	run audit
	[ "$status" -eq 1 ]
	[[ "$output" == *"'tier-tripwire' がワークフローにありません"* ]]
}

@test "赤: フック本体が消えると第3層の実体喪失として fail する" {
	make_sandbox
	rm "$SB/.claude/scripts/guard-dangerous.sh"
	run audit
	[ "$status" -eq 1 ]
	[[ "$output" == *"第3層の実体が消えています"* ]]
}
