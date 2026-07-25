---
id: R-000
title: <要件の一行表題>
tier: <S|A|B|C>
status: draft
ratified_by:
paths:
  - "<この要件が統べる機微コードのglob>"
negative_space:
  - "<このTierで起きてはならないことを1件ずつ列挙（このサービスの具体語で）>"
---

## 受け入れ基準

- <入力条件 → 期待結果を、テストで検証可能な粒度で1件ずつ列挙>

## 補足

<!--
記入の要点（詳細: docs/rules/requirements.md）
- id: 一意・不変・再利用禁止（R-<連番>）。
- tier: docs/rules/tiers.md の4軸で判定する。
- status: 内容が確定したら ratified に更新する（ratified の要件だけが req-coverage / tier-tripwire の
    ゲート対象になる。draft のままの要件に紐づくテストは dangling＝赤）。
- ratified_by: 任意の証跡（誰が/何が確定させたか）。
- 既存要件の意味の書き換え・削除はユーザーの了解を得てから行う（実装の都合で要件を変えない。ADR-008）。
- negative_space: Tier S/A 必須。抽象語でなくこのサービスの具体的な禁止事象を書き、
    adversarial テストで検証する（実装とは別コンテキストでの生成を推奨。docs/rules/requirements.md §6）。
-->
