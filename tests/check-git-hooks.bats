#!/usr/bin/env bats
# common/scripts/check-git-hooks.sh（git フックが作動する状態にあるかの検査）の回帰。
#
# この検査が守るのは「pre-push / commit-msg が**実際に走る**こと」。
# 外れ方が2種類あり、**この検査が要るのは後者のため**である。
#   - フックが落ちる                     → 気づける
#   - フックが「無いもの」として素通りする → 緑に見えて何も守らない（fail-open・気づけない）
# 後者は 2026-08-07 に sumai-desk と基盤リポの両方で実際に起きた形で、原因は絶対リンク。
# git は解決できないシンボリックリンクを「フックが無い」と同じに扱い、警告を出さない。
#
# 各ケースは「正常な構成を作ってから1箇所だけ壊す」（変異注入）。
# 壊す前が緑であることを毎回踏むので、検査が空撃ちになっていないことも同時に確認できる。
#
# 【CI を必ず unset する理由】
# 本体は CI ではフックを判定しない（CI ではフックを導入しないため）。bats が CI 上で走ると
# 全ケースが「スキップして 0」になり、**このテストファイル自体が空撃ちになる**。

SUT="${BATS_TEST_DIRNAME}/../common/scripts/check-git-hooks.sh"

setup() {
	unset CI
	# 本体は共通側の実体の所在を**自分自身の位置**から決めるので、偽の基盤レイアウトを
	# 作ってそこへ複製する（環境変数の裏口を本体に開けないため）。
	F="$BATS_TEST_TMPDIR/foundation"
	mkdir -p "$F/common/scripts" "$F/projects/proj"
	cp "$SUT" "$F/common/scripts/check-git-hooks.sh"
	for h in pre-push commit-msg; do
		printf '#!/bin/sh\nexit 0\n' > "$F/common/scripts/$h"
		chmod +x "$F/common/scripts/$h"
	done
	P="$F/projects/proj"
	git -C "$P" init -q
	HOOKS="$P/.git/hooks"
	mkdir -p "$HOOKS"
}

# make install-hooks が張るのと同じ形（相対リンク）。
install_ok() {
	ln -sfr "$F/common/scripts/pre-push"   "$HOOKS/pre-push"
	ln -sfr "$F/common/scripts/commit-msg" "$HOOKS/commit-msg"
}

run_sut() { run bash "$F/common/scripts/check-git-hooks.sh" "$P"; }

# ---- 緑 ----

@test "緑: 相対リンクで導入され、解決・実行できれば通る" {
	install_ok
	run_sut
	[ "$status" -eq 0 ]
}

@test "緑: 実体ファイル（symlink でない）のフックは相対判定の対象外" {
	# 参照方式では使わない形だが、手で置いたフックを赤にする理由は無い。
	printf '#!/bin/sh\nexit 0\n' > "$HOOKS/pre-push";   chmod +x "$HOOKS/pre-push"
	printf '#!/bin/sh\nexit 0\n' > "$HOOKS/commit-msg"; chmod +x "$HOOKS/commit-msg"
	run_sut
	# 実体ファイルは共通側を指していないので「すり替え」で赤になるのが正しい挙動。
	# ここで確認したいのは**絶対リンクとは違う理由**で落ちること。
	[ "$status" -eq 1 ]
	[[ "$output" == *"共通側の実体を指していません"* ]]
	[[ "$output" != *"絶対パス"* ]]
}

# ---- 赤: 今回のバグそのもの ----

@test "赤: 絶対リンクは、解決できていても赤にする（今回のバグ）" {
	install_ok
	# 変異注入: 相対 → 絶対。監査環境では**解決できてしまう**ので、
	# 存在・解決・実行権限だけを見る検査ではここが緑のまま通り抜ける。
	ln -sf "$F/common/scripts/pre-push" "$HOOKS/pre-push"
	[ -e "$HOOKS/pre-push" ]   # 解決はできる（＝「壊れていない」ように見える）
	[ -x "$HOOKS/pre-push" ]
	run_sut
	[ "$status" -eq 1 ]
	[[ "$output" == *"pre-push"* ]]
	[[ "$output" == *"絶対パス"* ]]
}

@test "赤: commit-msg 側の絶対リンクも独立に捕まえる" {
	install_ok
	ln -sf "$F/common/scripts/commit-msg" "$HOOKS/commit-msg"
	run_sut
	[ "$status" -eq 1 ]
	[[ "$output" == *"commit-msg"* ]]
	[[ "$output" == *"絶対パス"* ]]
}

# ---- 赤: その他の「黙って走らない」形 ----

@test "赤: 導入されていない" {
	install_ok
	rm "$HOOKS/pre-push"
	run_sut
	[ "$status" -eq 1 ]
	[[ "$output" == *"導入されていません"* ]]
}

@test "赤: リンク先を解決できない（dangling）" {
	install_ok
	ln -sfr "$F/common/scripts/does-not-exist" "$HOOKS/pre-push"
	run_sut
	[ "$status" -eq 1 ]
	[[ "$output" == *"解決できません"* ]]
}

@test "赤: 実行権限が無い（git は実行可能でないフックを走らせない）" {
	install_ok
	chmod -x "$F/common/scripts/pre-push"
	run_sut
	[ "$status" -eq 1 ]
	[[ "$output" == *"実行権限がありません"* ]]
}

@test "赤: 共通側でない実体へすり替えられている" {
	install_ok
	printf '#!/bin/sh\nexit 0\n' > "$F/projects/proj/evil"; chmod +x "$F/projects/proj/evil"
	ln -sfr "$F/projects/proj/evil" "$HOOKS/pre-push"
	run_sut
	[ "$status" -eq 1 ]
	[[ "$output" == *"共通側の実体を指していません"* ]]
}

@test "赤: 共通側の実体そのものが消えている" {
	install_ok
	rm "$F/common/scripts/pre-push"
	run_sut
	[ "$status" -eq 1 ]
	[[ "$output" == *"共通側の実体がありません"* ]]
}

# ---- 赤: core.hooksPath による無効化（見落とすと検査が空撃ちになる） ----

@test "赤: core.hooksPath が空ディレクトリを指すとフックは1本も走らない" {
	install_ok           # .git/hooks 側は正しく張られている（＝素朴な検査なら緑）
	mkdir -p "$P/nohooks"
	git -C "$P" config core.hooksPath nohooks
	run_sut
	[ "$status" -eq 1 ]
	[[ "$output" == *"導入されていません"* ]]
}

@test "赤: core.hooksPath が解決できないディレクトリを指す" {
	install_ok
	git -C "$P" config core.hooksPath /nonexistent/hooks
	run_sut
	[ "$status" -eq 1 ]
	[[ "$output" == *"core.hooksPath"* ]]
}

@test "緑: core.hooksPath が相対指定でも、そこに正しく張られていれば通る" {
	mkdir -p "$P/myhooks"
	ln -sfr "$F/common/scripts/pre-push"   "$P/myhooks/pre-push"
	ln -sfr "$F/common/scripts/commit-msg" "$P/myhooks/commit-msg"
	git -C "$P" config core.hooksPath myhooks
	run_sut
	[ "$status" -eq 0 ]
}

# ---- worktree（--git-dir と --git-common-dir が食い違う） ----

@test "緑: worktree から見ても共有側の hooks を検査する" {
	install_ok
	git -C "$P" -c user.email=t@example.com -c user.name=t commit -q --allow-empty -m init
	git -C "$P" worktree add -q "$F/wt" -b wt
	run bash "$F/common/scripts/check-git-hooks.sh" "$F/wt"
	[ "$status" -eq 0 ]
}

@test "赤: worktree 専用ディレクトリにだけ張られたフックは走らない" {
	# --git-dir を見る実装だとここが緑になる。git が読むのは共有側だけなので、
	# 「張ったのに1回も走らない」状態がそのまま素通りする。
	git -C "$P" -c user.email=t@example.com -c user.name=t commit -q --allow-empty -m init
	git -C "$P" worktree add -q "$F/wt" -b wt
	mkdir -p "$P/.git/worktrees/wt/hooks"
	ln -sfr "$F/common/scripts/pre-push"   "$P/.git/worktrees/wt/hooks/pre-push"
	ln -sfr "$F/common/scripts/commit-msg" "$P/.git/worktrees/wt/hooks/commit-msg"
	run bash "$F/common/scripts/check-git-hooks.sh" "$F/wt"
	[ "$status" -eq 1 ]
	[[ "$output" == *"導入されていません"* ]]
}

# ---- CI ----

@test "CI では判定しない（フックを導入しないため。ゲートは workflow が直接回す）" {
	install_ok
	ln -sf "$F/common/scripts/pre-push" "$HOOKS/pre-push"   # 壊れていても
	CI=1 run bash "$F/common/scripts/check-git-hooks.sh" "$P"
	[ "$status" -eq 0 ]
	[[ "$output" == *"CI ではフックを導入しない"* ]]
}

# ---- fail-closed（呼び出し方の誤り） ----

@test "exit 2: 引数不足は fail-closed" {
	run bash "$F/common/scripts/check-git-hooks.sh"
	[ "$status" -eq 2 ]
}

@test "exit 2: 存在しないプロジェクトルートは fail-closed" {
	run bash "$F/common/scripts/check-git-hooks.sh" "$F/nope"
	[ "$status" -eq 2 ]
}

# ---- 未判定（自分のリポジトリを持たない＝守るべき push ゲートが無い） ----

@test "未判定: git リポジトリでないディレクトリ（生成直後のサービス等）" {
	mkdir -p "$F/plain"
	run bash "$F/common/scripts/check-git-hooks.sh" "$F/plain"
	[ "$status" -eq 0 ]
	[[ "$output" == *"git リポジトリではない"* ]]
}

@test "未判定: 上位リポジトリの一部であって単独のリポジトリではない場合" {
	# 生成直後のサービスを基盤の projects/ 配下に置いた形。ここを「git リポジトリか」だけで
	# 見ると**基盤リポのフックを見て緑**になり、別のリポジトリの結果でこのプロジェクトを
	# 緑にしてしまう。
	git -C "$P" -c user.email=t@example.com -c user.name=t commit -q --allow-empty -m init
	install_ok                      # 親（$P）側は正しく張られている
	mkdir -p "$P/newsvc"
	run bash "$F/common/scripts/check-git-hooks.sh" "$P/newsvc"
	[ "$status" -eq 0 ]
	[[ "$output" == *"単独の git リポジトリではない"* ]]
}
