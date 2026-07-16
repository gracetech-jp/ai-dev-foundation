---
name: extract-requirements
description: 既存の仕様書・設計メモ・コードから要件(R-id)の下書きを生成する。出力は保護外のスクラッチ .req-drafts/ のみで、docs/requirements/ には絶対に書かない（人間が中身を批准して移す）。「要件を抽出」「仕様書を要件化」「既存要件のID後付け」等の依頼で使う。
---

# extract-requirements — 既存仕様から要件下書きを生成する

要件トレーサビリティ導入時、既存サービスの散在した仕様を `docs/requirements/` の
一意ID付き資産へ後付けするための**下書き生成**を支援する。設計の正: `docs/rules/requirements.md`。

## 絶対規則（自己完結ループの防止）

- **`docs/requirements/` には絶対に書かない**。ここは人間批准の永続資産であり、`settings.json` deny＋
  `guard-dangerous.sh` で機械的に書き込み拒否される（書けもしない）。スキルとしても書こうとしない。
- **出力先は保護外のスクラッチ `.req-drafts/` のみ**。ここに下書き `.md` を生成する。
- **`status: draft` 固定**。`status: ratified`・`ratified_by`・`tests_ratified_by`・`tests_ratified_sha`・
  `tier` の確定値を**LLMが埋めない**（tier は暫定候補をコメントで提案するに留める）。批准は人間だけが行う。
- adversarial テスト・negative_space は**候補の提示まで**。実装LLMがテストを生成・マーカー付与しない
  （`docs/rules/requirements.md` §6）。

## 手順

1. 対象の仕様書・設計メモ・コードを読み、要件の粒度に切り出す。
2. 各要件について `.req-drafts/R-<連番>-<スラッグ>.md` を生成する（front-matter は
   `docs/rules/requirements.md` §2 のスキーマ。確定値は空、暫定 tier はコメントで提案）。
3. `negative_space` 候補（起きてはいけないこと）と受け入れ基準の草案を本文に書く。
4. 生成物の一覧と、各要件の要点・要確認事項を人間に報告する。**ここで完了**。

## 人間による昇格・批准（スキルは実行しない・案内のみ）

以下は人間が行う。スキルは手順を提示するだけ。

1. `.req-drafts/` の下書きを人間がレビューし、tier・受け入れ基準・negative_space を確定する。
2. `git mv .req-drafts/R-xxx-*.md docs/requirements/` で正式ディレクトリへ移す。
3. 要件↔テストのマーカーを付け、妥当性を確認したうえで `tests_ratified_by` を記入。
4. `bash scripts/check-requirements-coverage.sh --sha R-xxx` で `tests_ratified_sha` を算出し記入。
5. `status: ratified`・`ratified_by` を記入して **人間が commit**（要件パスは CODEOWNERS＋ブランチ保護で
   レビュー必須。`docs/rules/git.md`）。

> スキルが `ratified` を書く／`docs/requirements/` に触れることは禁止。下書き提示までが責務。
