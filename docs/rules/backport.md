# 共通基盤の配布と順輸入（共通リポ → サービス・一方通行）

共通基盤の流れは**一方通行**。共通リポの `new-service.sh` でサービスを作った後も、
共通所有ファイルの改善は**共通リポで直接行い**、既存の各サービスは**順輸入で取り込む**。

> **2026-07-24 逆輸入（サービス → 共通）は廃止した（ADR-009）**。旧 `backport-to-common.sh` は削除。
> 共通所有ファイル（下記）は**サービス側で編集も還流もしない**。サービス側では deny＋
> `guard-dangerous.sh` により編集が機械的に拒否される（更新の正規経路は順輸入のみ）。

```
共通リポ ──(new-service.sh で雛形展開)──▶ サービス
   │
   └───(sync-from-common.sh で取込)──────▶ サービス
```

---

## 仕組み

- **`.backport-manifest`（共通リポ側）**：共通所有ファイルの一覧＝順輸入で配布される範囲の正。
  名称は既存サービスの `sync-from-common.sh` が参照するため互換維持（実体は「配布マニフェスト」）。
  変更は共通リポで直接行う。サービスへは配布しない。
- **`scripts/sync-from-common.sh`**：共通 → サービスの取込。**共通リポ側**のマニフェストを正として
  共通所有ファイルを取り込む（新規追加あり・削除なし・自動バックアップ・dry-run 付き。設計理由: ADR-005）。
  自身もマニフェストに載っており自己ホスティング（ツールの改善も取込で伝播する）。

## 共通所有ファイルの範囲（サービス側で触らない領域）

**「新規サービス構築後、仕組みを疑わなければ触ることがないファイル」だけ**が共通所有＝編集禁止の対象。

- 🔒 編集禁止（deny＋guard で機械拒否・更新は順輸入のみ）:
  `CLAUDE.md`・`docs/rules/`・`.claude/settings.json`・`.claude/scripts/`（guard・session-start）・
  配布 skills（extract-requirements / verify-request）・配布 agents（consistency-auditor / security-reviewer）・
  `scripts/`（pre-push・commit-msg・check-coverage.sh・check-requirements-coverage.sh・
  check-tier-tripwire.sh・sync-from-common.sh）
- ✏️ **サービス側で編集が前提の箇所は対象外**（例外）:
  `SERVICE.md`・`README.md`・`Makefile`（ターゲット実装）・`scripts/audit-consistency.sh`（肉付け）・
  `docs/requirements/`・`docs/service-rules/`・`docs/decisions/`・`.devcontainer/`・
  `.github/workflows/ci.yml`（deploy 等の追加）・`.gitignore`（依存の追記）・`.env.example`・
  `.coverage-floor`・`.req-coverage-baseline`・`.tier-tripwire-allow`・サービス独自の skills/agents の追加

共通所有ファイルに直したいことができたら、それは**共通リポで直す合図**（このリポジトリなら直接編集、
サービス作業中なら共通リポ側で編集して順輸入）。ローカルに固有の権限等が必要なら
`.claude/settings.local.json` を使う（共通所有の `settings.json` は触らない）。

## 最重要の規律：共通所有ファイルはスタック中立に保つ

- ✅ 共通所有に置く：枠組み・原則・言語非依存の運用ルール（品質ゲートの原則、整合性監査の"型"、git運用 等）。
- ❌ 共通所有に置かない：特定の言語/FW/ORM/決済/インフラ、具体的な `lint`/`test` コマンド、ドメイン固有の識別子。
  → `SERVICE.md` や `docs/service-rules/` へ分離する。

## 順輸入（共通 → サービス）の使い方

```bash
# 1) プレビュー（差分表示のみ。共通リポ側マニフェスト由来の対象一覧と diff を確認）
./scripts/sync-from-common.sh <共通リポのパス>

# 2) 問題なければ適用（上書き分は .sync-backup-*/ に自動退避。新規の共通ルールは追加される）
./scripts/sync-from-common.sh <共通リポのパス> --apply

# 3) サービス側で差分を確認してコミット
git status && git diff
```

- 対象の解決は**共通リポ側の `.backport-manifest` が正**（サービス側の改変で取込範囲が歪まないように）。
- 新規ファイルも既定で追加する（新規＝共通リポで生まれた新ルールであり、配布がこのツールの目的そのもの）。
- サービス側の対象ファイルが dirty なら中断する（共通所有ファイルはそもそも編集しない原則。
  dirty は原則違反のサインなので、差分を確認して破棄または共通リポ側で作り直す）。
- **profiles/ 由来の骨格（`.claude/` 配下・`.devcontainer/`・`.github/workflows/`・`Makefile`・監査雛形等）は
  マニフェスト対象外＝手動同期**（サービス側の配置とパスが 1:1 対応しないため。`.backport-manifest` 注1）。
  基盤側で骨格を変更したら、既存サービスの同パスへ手でコピーして揃える
  （root↔`profiles/_base` の複製ずれは基盤の監査が機械検出する）。
  この手動コピーは共通所有ロックの**例外として通る**が、条件は「`cp`/`rsync`/`install` の
  **コピー元（第1引数）が `profiles/_base/` 配下**であること」。コピー先だけに書いても通らない。

  ```bash
  # 例: 基盤の骨格をサービスへ手で揃える（この形だけがロックを通る）
  cp ~/projects/ai-dev-foundation/profiles/_base/.claude/scripts/guard-dangerous.sh .claude/scripts/guard-dangerous.sh
  ```

## いつ順輸入するか

- 共通リポに改善・新ルールが入ったと知ったとき。目安として**作業の区切りで dry-run を流し**、
  差分があれば取り込む（solo 運用では定期スケジュールを課さない。2026-07-23 に週次目安を撤去）。
- サービス固有に閉じる変更は共通所有ファイルに書かない（`SERVICE.md`・`docs/service-rules/` へ）。
