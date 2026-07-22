---
id: R-000
title: <要件の一行表題>
tier: <S|A|B|C>
status: draft
ratified_by:
tests_ratified_by:
tests_ratified_sha:
paths:
  - "<この要件が統べる機微コードのglob>"
test_assets:
  - "<ハッシュ対象に含めるテスト/フィクスチャのglob>"
negative_space:
  - "<このTierで起きてはならないことを1件ずつ列挙（このサービスの具体語で）>"
---

## 受け入れ基準

- <入力条件 → 期待結果を、テストで検証可能な粒度で1件ずつ列挙>

## 補足

<!--
記入の要点（詳細: docs/rules/requirements.md）
- id: 一意・不変・再利用禁止（R-<連番>）。
- tier: docs/rules/tiers.md の4軸で判定。人間が批准する。
- status: draft→ratified は人間の commit のみ。LLM は当ディレクトリを書けない。
- tests_ratified_by / tests_ratified_sha: Tier S/A で必須。
    tests_ratified_sha は批准時点のテスト資産群の正規化ハッシュ（算出法は requirements.md §7）。
- negative_space: Tier S/A 必須。抽象語でなくこのサービスの具体的な禁止事象を書く。
    adversarial テストは実装LLMに書かせない（人間執筆、または別コンテキストのモデル生成＋人間レビュー）。
-->
