# 共通資産の所有と参照（実体は共通リポに1つだけ）

共通資産は**共通リポ `ai-dev-foundation` にのみ実体を置き、各プロジェクトは参照する**。
プロジェクト側に複製を作らない。複製が無いので「同期」も「還流」も存在しない。

> **経緯**: 2026-07-24 に逆輸入（プロジェクト → 共通）を廃止し（ADR-009）、
> 2026-07-30 に順輸入（共通 → プロジェクトへの配布・`sync-from-common.sh`）も廃止した（ADR-010）。
> 旧 `.backport-manifest`・`scripts/sync-from-common.sh` は削除済み。本ファイルの旧名は `backport.md`。

```
共通リポ ──(new-service.sh で雛形展開＝プロジェクト固有ファイルのみ)──▶ プロジェクト
   ▲
   └────────────(実行時に参照。複製しない)─────────────────────────────┘
```

---

## 参照の仕組み

すべての解決はマーカーファイル **`.ai-dev-foundation-root`** を起点にする。共通リポのルートに
置かれており、プロジェクトから**上方向に探索**して見つける。階層の深さを仮定しないので、
ディレクトリ構成を変えても壊れない。実装は `common/scripts/resolve-common.sh`。

そのため**プロジェクトは共通リポの `projects/` 配下に置く**（`new-service.sh` の生成先もそこ）。
共通リポの兄弟に置くと解決に失敗し、`make` が即エラーになる（fail-closed）。

| 共通資産 | プロジェクトからの参照方法 |
|---|---|
| `CLAUDE.md` | Claude Code が起動位置から上位ディレクトリを遡り、見つかった `CLAUDE.md` をすべて連結する |
| `docs/rules/` | SessionStart フック `session-start-rules.sh` がマーカーを上方探索し、共通側から索引を注入する |
| `common/make/contract.mk`・`gates.mk` | プロジェクトの `Makefile` が `include $(COMMON_ROOT)/common/make/...` する |
| `common/scripts/check-*.sh` | `gates.mk` が `$(COMMON_ROOT)/common/scripts/` を直接実行する |
| `common/scripts/pre-push`・`commit-msg` | `make install-hooks` が `.git/hooks/` から共通側へ `ln -sf` する |
| CI のゲート | `.github/actions/` の composite action を `uses:` で参照する（CI には共通リポが checkout されないため） |

解決に失敗したときは**必ず fail-closed / fail-loud** にする。「共通ルールが見つからないので
ルール無しで続行」は、この基盤が繰り返し潰してきた失敗類型そのもの。

## 参照にできず複製が残るもの

- **composite action の同梱スクリプト**（`.github/actions/*/check-*.sh`）
  … `$GITHUB_ACTION_PATH` から読むため同梱が必須。
- **`profiles/_base/.devcontainer/Dockerfile`** … `new-service.sh` が `profiles/_base` を読むため。
- **`.claude/` 骨格**（`settings.json`・配布 skills/agents）
  … Claude Code がプロジェクトルートを見るため。共通リポでは `profiles/_base/.claude/...` に
  置かれるものがプロジェクトでは `.claude/...` に来るなど**パスが 1:1 対応しない**。
  **フック本体（guard-dangerous.sh・session-start-rules.sh）は 2026-08-04 に対象外になった**
  （ADR-012 フェーズ2）。実体は共通リポの `.claude/scripts/` 1箇所だけで、devcontainer が
  `/home/node/.claude`（ユーザースコープ）へマウントして配る。**手動同期は不要**であり、
  配布側に複製が生えたら監査の検査(3)が赤にする。

これらは**基盤側で変更したら手でコピーして揃える**。複製ずれは基盤の整合性監査が機械検出する
（`audit-consistency.sh` 検査(6)(10)）。手動コピーは共通所有ロックの**例外として通る**が、
条件は「`cp`/`rsync`/`install` の**コピー元（第1引数）が `profiles/_base/` 配下**であること」。
コピー先だけに書いても通らない。

```bash
# 例: 基盤の骨格をプロジェクトへ手で揃える（この形だけがロックを通る）
cp ~/projects/ai-dev-foundation/profiles/_base/.claude/agents/consistency-auditor.md .claude/agents/consistency-auditor.md
```

## 共通所有ファイルの範囲（プロジェクト側で触らない領域）

**「新規プロジェクト構築後、仕組みを疑わなければ触ることがないファイル」だけ**が共通所有。

- 🔒 プロジェクト側で編集も**複製の作成**もしない（deny＋guard で機械拒否）:
  `CLAUDE.md`・`docs/rules/`・`.claude/settings.json`・`.claude/scripts/`（共通側の実体。プロジェクトには置かない）・
  配布 skills（extract-requirements / verify-request）・配布 agents（consistency-auditor /
  security-reviewer）・`scripts/`（pre-push・commit-msg・check-coverage.sh・
  check-requirements-coverage.sh・check-tier-tripwire.sh）
- ✏️ **プロジェクト側で編集が前提の箇所は対象外**（例外）:
  `PROJECT.md`・`README.md`・`Makefile`（ターゲット実装）・`scripts/audit-consistency.sh`（肉付け）・
  `docs/requirements/`・`docs/service-rules/`・`docs/decisions/`・`.devcontainer/`・
  `.github/workflows/ci.yml`（deploy 等の追加）・`.gitignore`（依存の追記）・`.env.example`・
  `.coverage-floor`・`.req-coverage-baseline`・`.tier-tripwire-allow`・独自の skills/agents の追加

ロックの意味は「配られた複製を編集させない」ではなく**「複製をプロジェクト側に発生させない」**。
共通所有ファイルに直したいことができたら、それは**共通リポで直す合図**。
ローカルに固有の権限等が必要なら `.claude/settings.local.json` を使う（共通所有の
`settings.json` は触らない）。

## 最重要の規律：共通資産はスタック中立に保つ

- ✅ 共通に置く：枠組み・原則・言語非依存の運用ルール（品質ゲートの原則、整合性監査の"型"、git運用 等）。
- ❌ 共通に置かない：特定の言語/FW/ORM/決済/インフラ、具体的な `lint`/`test` コマンド、ドメイン固有の識別子。
  → `PROJECT.md` や `docs/service-rules/` へ分離する。

## 共通資産を変更するとき

共通リポで直接編集する。**各プロジェクトは次に `make` を回した時点で新しい実体を参照する**ので、
取り込み作業は要らない（これが参照方式の主目的）。

ただし上記「参照にできず複製が残るもの」に触れた場合だけは手動同期が必要。忘れると
新規プロジェクトだけが古いガードで生まれる「サイレント分岐」になるため、監査が機械検出する。
