#!/usr/bin/env bash
# run-gates.sh — 品質ゲートを順に実行し、soft/hard を判定してまとめて結果を返す（共通・スタック中立）。
#
# 【なぜスクリプトなのか】
# この判定は 2026-07-23 から profiles/_base/.github/workflows/ci.yml の runCmd に直書きされていた。
# YAML 内のシェルは bats で検証できず、**ゲートの判定ロジック自体がテストされていない**状態だった。
# ADR-011 で CI を reusable workflow へ寄せるにあたり、判定を共通スクリプトとして実体化する。
# これによりローカル（人間・pre-push）と CI が同じ経路を通り、判定そのものを回帰テストできる。
#
# 【なぜ「失敗しても続ける」のか】
# GitHub Actions の step は「失敗＝即中断」か continue-on-error（＝結果を無視）の二択で、
# 「失敗を記録して続行し、最後にまとめて落とす」を YAML では表現できない。
# 1回の実行で全ゲートの結果を出すには、この形をシェルで持つしかない
# （配布 CI が gates 1ジョブに統合されているのも同じ理由）。
#
# 【TODO 契約（exit 3）を出力で判定する理由】
# GNU make はレシピ失敗時に自身の終了コードを 2 へ正規化するため、**exit code では TODO を判別できない**。
# make が決定論的に出すエラー行「make: *** [...] Error 3」で識別する
# （ターゲットの任意出力に依存しない＝誤 soft を排除する）。契約: docs/rules/quality-gates.md §4。
#
# 使い方:
#   run-gates.sh <project-root> <mode:target> [<mode:target> ...]
#     mode = hard     … 失敗したら red（req-coverage / tier-tripwire / audit-all）
#            softable … 失敗が TODO（exit 3）なら warning、それ以外は red（lint / test / audit-deps）
#            auto     … .coverage-floor を読んで切り替える（coverage 専用）
#   例: run-gates.sh . hard:audit-all softable:lint softable:test auto:coverage hard:req-coverage
#
# 終了コード: 0=全ゲート通過（soft 扱いを含む）/ 1=1つ以上が red / 2=呼び出し方の誤り（fail-closed）

set -u

die() { echo "[gates] ❌ $1" >&2; exit 2; }

[ "$#" -ge 2 ] || die "使い方: run-gates.sh <project-root> <mode:target> [...]（fail-closed）"

PROJECT_ROOT="$1"; shift
[ -d "$PROJECT_ROOT" ] || die "プロジェクトルートがありません: $PROJECT_ROOT"

fail=0

# make が TODO 契約（exit 3）で落ちたか。出力行で判定する（上記の理由）。
is_todo() { printf '%s\n' "$1" | grep -qE '^make(\[[0-9]+\])?: \*\*\* .* Error 3$'; }

# GitHub Actions のアノテーション。CI 外では単なる行として出るだけで害はない。
warn() { echo "::warning::[gates] $1"; }

run_one() { # <mode> <target>
	local mode="$1" target="$2" out rc
	out="$(make -C "$PROJECT_ROOT" "$target" 2>&1)"; rc=$?
	printf '%s\n' "$out"
	if [ "$rc" -eq 0 ]; then
		echo "[gates] ✅ $target"
		return 0
	fi
	case "$mode" in
		softable)
			if is_todo "$out"; then
				warn "$target は未実装(TODO=exit 3)のため soft 扱い（実装すると自動で red 化）"
				return 0
			fi
			;;
		soft-any)
			# 理由を問わず soft。coverage が floor=0 のときだけこの扱いになる（下記 auto）。
			warn "$target は soft 扱い（floor=0。実装かつ floor>0 で自動 red 化）"
			return 0
			;;
	esac
	echo "[gates] ❌ $target 失敗（red）"
	fail=1
}

for spec in "$@"; do
	case "$spec" in
		*:*) ;;
		*) die "不正な指定です: '$spec'（<mode>:<target> の形で渡すこと）" ;;
	esac
	mode="${spec%%:*}"
	target="${spec#*:}"
	[ -n "$target" ] || die "ターゲット名が空です: '$spec'"
	case "$mode" in
		hard|softable) ;;
		auto)
			# カバレッジのラチェットは floor=0 の間は何も守っていないため soft。
			# floor を 1 以上にした時点で自動的に hard へ移行する（人手の設定変更を要さない）。
			floor="$(cat "$PROJECT_ROOT/.coverage-floor" 2>/dev/null || echo 0)"
			if [ "$floor" = "0" ]; then mode="soft-any"; else mode="hard"; fi
			;;
		*) die "不正な mode です: '$mode'（hard|softable|auto）" ;;
	esac
	run_one "$mode" "$target"
done

if [ "$fail" -ne 0 ]; then
	echo "[gates] ❌ 1つ以上のゲートが red です。"
	exit 1
fi
echo "[gates] ✅ 全ゲート通過"
