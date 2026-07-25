---
name: extract-requirements
description: 既存の仕様書・設計メモ・コードから要件(R-id)を起こして docs/requirements/ に作成する（批准レス運用・ADR-008）。新規は status: draft で作成し、ユーザー確認後に ratified 化する。「要件を抽出」「仕様書を要件化」「既存要件のID後付け」等の依頼で使う。
---

# extract-requirements — 既存仕様から要件を起こす

要件トレーサビリティ導入時、既存サービスの散在した仕様を `docs/requirements/` の
一意ID付き資産へ後付けする作業を支援する。設計の正: `docs/rules/requirements.md`。

## 規則（自己完結ループの防止）

- **出力先は `docs/requirements/` 直接でよい**（旧 `.req-drafts/` 経由は 2026-07-24 批准レス化・ADR-008 で廃止）。
- **新規要件は `status: draft` で作成**し、内容の一覧をユーザーに報告する。`ratified` への更新は
  ユーザーが内容を確認した後に行う（確認前に ratified にしない）。
- **既存要件の意味の書き換え・削除はしない**。抽出中に既存要件との矛盾を見つけたら、変更せず
  ユーザーに報告する（`docs/rules/requirements.md` §3）。
- adversarial テスト・negative_space の候補は提示してよい。adversarial テストの実装は、
  抽出とは別コンテキストでの生成を推奨（`docs/rules/requirements.md` §6）。

## 手順

1. 対象の仕様書・設計メモ・コードを読み、要件の粒度に切り出す。
2. 各要件について `docs/requirements/R-<連番>-<スラッグ>.md` を作成する（front-matter は
   `docs/rules/requirements.md` §2 のスキーマ。`status: draft`・tier は4軸判定の根拠を添える）。
3. `negative_space` 候補（起きてはいけないこと）と受け入れ基準の草案を本文に書く。
4. 生成物の一覧と、各要件の要点・tier 判定根拠・要確認事項をユーザーに報告する。
5. ユーザーの確認が取れた要件から `status: ratified` に更新し、テストへ `@req` マーカーを付けて
   `make req-coverage` が緑になることを確認する。
   （マーカーと要件ファイルは**必ず同一コミット**に含める。要件が無い状態でマーカーだけ commit
   すると「dangling: マーカーに対応する要件が無い」で赤になる）
