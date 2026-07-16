# Git運用ガイドライン

## ブランチ戦略
main              # 本番相当・直接push禁止

└── feature/xxx   # 機能追加

└── fix/xxx       # バグ修正

└── docs/xxx      # ドキュメントのみ

## コミットメッセージ（Conventional Commits）
feat: ユーザー認証機能を追加

fix: ログイン時のセッション切れ問題を修正

docs: API仕様書を更新

test: ユーザー登録のテストを追加

refactor: 認証ロジックをサービス層に移動

chore: 依存パッケージを更新

## ルール
- 1コミット1目的（複数の変更を混在させない）
- コミット前に`git diff`で変更内容を確認する
- main への直接pushは原則禁止（例外は下記「開発フェーズと main 直接 push」）
- マージ前にセルフレビューを行う

## 開発フェーズと main 直接 push
- **原則**: main への直接 push は禁止。`feature/xxx` 等のブランチを切り、セルフレビューを経てマージする
- **例外**: MVP開発フェーズ中のリポジトリに限り、main への直接 push を許可する（開発者1人・未リリースの立ち上げ期に、ブランチ運用のオーバーヘッドより速度を優先するため）
- **例外の除外（要件パス）**: 上の MVP 例外があっても、**要件パス（`docs/requirements/**`）と要件枠組みルール（`docs/rules/tiers.md`・`docs/rules/requirements.md`）・ゲート緩和口（`.req-coverage-baseline`・`.tier-tripwire-allow`）の変更は、常に PR＋人間批准（CODEOWNERS レビュー）を必須**とし、main 直 push を許さない。要件を自己完結で書き換えて緑にする経路を塞ぐため（LLM編集封鎖の主防壁）
- **フェーズの判定**: 現在フェーズは各リポジトリ側に明記する（サービスリポ: `SERVICE.md` 冒頭、基盤リポ: `README.md`）。「フェーズ: MVP」の明記がある間のみ例外が有効。明記が無いリポジトリは原則（直接push禁止）に従う
- **切替条件**: 次のいずれかが最初に起きた時点で MVP フェーズを終了し、フェーズ表記を「運用」に更新してブランチ運用＋レビュー経由へ移行する
  1. 本番相当環境への初回リリース
  2. 開発者が2人以上になった
- フェーズ表記の更新はコミットとして記録し、以後 CI・レビュー運用の前提とする

## 要件パスのブランチ保護（手動セットアップ・要件のLLM編集封鎖の主防壁）

CODEOWNERS（`.github/CODEOWNERS`）は「誰のレビューが要るか」を宣言するだけで、**それ単体では強制されない**。
サーバ側（GitHub）のブランチ保護／Ruleset で有効化して初めて強制力を持つ。これは**サーバ側設定であり
リポジトリのファイルにはコミットできない**ため、各リポジトリで人間が一度だけ手動設定する。
`settings.json` deny と `guard-dangerous.sh` は補助的な多層防御にすぎず、**主防壁はこのブランチ保護＋CODEOWNERS**。

**手動セットアップ・チェックリスト**（GitHub → Settings → Rules/Branches）:
- [ ] `main` に Ruleset（または classic branch protection）を作成する
- [ ] 「Require a pull request before merging」を有効化する
- [ ] 「Require review from Code Owners」を有効化する（CODEOWNERS を強制）
- [ ] 「Do not allow bypassing the above settings」相当を有効化し、管理者もバイパス不可にする
- [ ] 必須ステータスチェックに `req-coverage` / `tier-tripwire` / `audit` / `test` を含める
- [ ] 設定後、`docs/requirements/**` を変更する PR で Code Owner レビューが実際に要求されることを1度確認する

> 未設定の場合、`scripts/audit-consistency.sh` の「要件パスのブランチ保護確認」が警告で surface する
> （API 不可環境ではスキップ＋警告）。恒久的な担保はこの手動設定で行う。

## コミット粒度の目安
- 1つの機能追加 = 1コミット
- バグ修正 = 1コミット（再現テスト + 修正を同一コミット）
- リファクタリングは機能変更と混在させない
