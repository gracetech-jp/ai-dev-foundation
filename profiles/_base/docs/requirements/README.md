# 要件（このサービスの一次要件）

このディレクトリは、このサービスの要件を**永続資産**として置く（批准レス運用: 基盤 ADR-008）。
CIが緑でも要件が未達なら不合格、を機械判定できる土台。

- 形式・採番の規約: `docs/rules/requirements.md`
- Tier の定義: `docs/rules/tiers.md`
- negative space（起きてはいけないこと）の固定資産: `INVARIANTS-template.md` を複製して埋める
- 新しい要件は `R-000-template.md` を複製し、次の連番で作る（IDは不変・再利用禁止）

## ディレクトリ構成

```
docs/requirements/
├── README.md               # このファイル（運用）
├── R-000-template.md       # 要件の雛形（複製して次の連番で作る）
└── INVARIANTS-template.md  # negative space（起きてはいけないこと）の雛形
```

## 運用（重要）

- 要件は LLM も直接生成・編集できる。新規は `status: draft` で起こし、内容確定後に `ratified` へ更新する
  （ratified の要件だけがゲート対象。draft のままの要件に紐づくテストは dangling＝赤）。
- **既存要件の意味変更・緩和・削除はユーザーの了解を得てから**行い、理由をコミットに残す。
  テストを緑にする目的で要件側を動かすことは禁止（`docs/rules/requirements.md` §3）。

## 要件一覧

| ID | 表題 | Tier | status |
|---|---|:--:|:--:|
| （ここに ratified 要件を追記） | | | |
