# ADR-004: Claude Code のガードレールを選択的に追跡し全サービスへ配布する

## 日付
2026-07-11

## ステータス
採用済み

## 背景
AI エージェント（Claude Code）による破壊的操作・秘密情報アクセスを、プロンプトの善意だけに頼ると
確実に防げない。加えて `.claude/` には認証情報・セッションログ等の**追跡してはいけない**ファイルと、
チームで共有すべき**安全設定**（権限・フック・skills・subagents）が混在する。丸ごと `.gitignore` すると
安全設定が新規 clone や2人目以降へ配布されず、丸ごと追跡すると秘密が漏れる。

## 決定
`.claude/` を丸ごと除外したうえで、`settings.json`・`scripts/`・`skills/`・`agents/` のみを
`!` で選択的に追跡へ戻す。ガードレールは多層で機械化する：
- `permissions.deny`：破壊的 git 操作・秘密ファイル（`.env`/鍵/ssh/aws/gcloud 等）の Read を拒否。
- PreToolUse フック `guard-dangerous.sh`：deny をすり抜ける表記ゆれ・チェイン実行・bash 経由の秘密読み取りを遮断。
- `permissions.ask`：マイグレーション・パッケージ導入・ワークフロー実行に実行前確認。
- SessionStart フック：`SERVICE.md`・`docs/rules/` を毎セッション注入。
これら一式を `new-service.sh` で全サービスへ配布する。

## 理由
- 「プロンプト任せにしない・機械的ゲート」を deny＋フックの二重で担保できる（プロンプト遵守のみに頼らない）。
- 選択的追跡により、秘密は追跡せず・安全設定だけをチーム共有＆新規 clone へ配布できる。
- 組織全体で強制したい制御（`disableBypassPermissionsMode` 等）は project 設定に置けないため、
  managed-settings（管理者スコープ）に委ねる方針を `docs/rules/security.md` に明記した。

## 注意事項
- root と `templates/` の `.claude/` は別実体（手動同期）。guard の依存 `jq` は両 Dockerfile に必要で、
  片側の退化を `audit-consistency.sh` が検出する。
- deny/フックは READ・実行を塞ぐが、秘密の**コミット**は塞がない。`.gitignore` の秘密パターンと CI の
  秘密スキャン（gitleaks）で別途担保する。

## 結果
新規サービスは生成時点でガードレール一式を継承する。破壊的操作・秘密アクセスは決定論的に遮断され、
安全設定はチームへ配布される。
