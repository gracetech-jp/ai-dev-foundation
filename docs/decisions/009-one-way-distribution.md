# ADR-009: 逆輸入の廃止と共通所有ファイルの一方通行配布（サービス側編集の機械封鎖）

記録日: 2026-07-24 ／ 対象リポ: ai-dev-foundation ／ 状態: 一部置換済み（→ 010・012。配布＝順輸入は廃止／防御の主軸はコンテナ隔離へ移動。共通所有ファイルのロックの決定は現役）

## 背景 — 解決したかった問題

ADR-003 は「サービス内で育った改善を逆輸入（`backport-to-common.sh`）で共通リポへ還流する」双方向
ループを定めていた。しかし実運用では、共通所有ファイルをサービス側で編集できること自体が
分岐・還流漏れ・上書き事故の温床であり、solo 運用では「改善は基盤リポで直接行う」方が単純で速い。

## 決定

**共通基盤の流れを一方通行にする（共通リポ → サービスのみ）。**

- **逆輸入（サービス → 共通）を廃止**: `scripts/backport-to-common.sh` を削除。サービスへの配布・
  `.backport-manifest` のサービス側配布も停止（マニフェストは共通リポ側の配布範囲定義としてのみ残る。
  ファイル名は既存サービスの `sync-from-common.sh` が参照するため互換維持）。
- **共通所有ファイルはサービス側で編集禁止（機械封鎖）**: 配布する `settings.json` の deny と
  `guard-dangerous.sh`（bash 経由の書込遮断）で二重に拒否する。更新の正規経路は順輸入
  （`sync-from-common.sh`）のみ。
- **例外＝サービス側で編集が前提の箇所は封鎖しない**。封鎖対象は「新規サービス構築後、仕組みを
  疑わなければ触ることがないファイル」に限る（範囲の正: `docs/rules/common-assets.md`）。

### 封鎖対象（deny＋guard）

`CLAUDE.md`・`docs/rules/**`・`.claude/settings.json`・`.claude/scripts/`（guard・session-start）・
配布 skills（extract-requirements / verify-request）・配布 agents（consistency-auditor / security-reviewer）・
`scripts/`（pre-push・commit-msg・check-coverage.sh・check-requirements-coverage.sh・check-tier-tripwire.sh・
sync-from-common.sh）

### 封鎖しない（サービス側編集が前提）

`PROJECT.md`・`README.md`・`Makefile`（ターゲット実装）・`scripts/audit-consistency.sh`（肉付け）・
`docs/requirements/**`・`docs/service-rules/**`・`docs/decisions/**`・`.devcontainer/**`・
`.github/workflows/ci.yml`・`.gitignore`・`.env.example`・`.coverage-floor`・`.req-coverage-baseline`・
`.tier-tripwire-allow`・サービス独自 skills/agents の**追加**（配布物の丸ごとディレクトリ封鎖はしない）

## 実装上の設計判断

- **基盤リポ自身は封鎖対象外**（共通所有ファイルの編集元のため）。guard は `profiles/_base/` の存在で
  基盤リポを決定論的に判定してスキップする。settings.json の deny は静的なため、ロック deny は
  **配布側（`profiles/_base`・各プロファイル）にのみ置き、基盤 root には置かない**。この意図的な
  配布分岐は整合性監査が「ロック deny を差し引いて同値比較＋ロック deny の存在（退化検出）」で機械管理する。
- **順輸入は封鎖と両立する**: `sync-from-common.sh` の起動コマンドは書込系コマンドと共起しないため
  guard を素通りし、スクリプト内部の cp はフック検査の対象外。deny は Claude のツール直接編集のみ塞ぐ。
- ローカル固有の権限・環境は `.claude/settings.local.json` に書く（共通所有の `settings.json` は触らない）。
- 検証は R-002（bats。deny 回避の bash 書込・基盤スキップ・sync 素通しの回帰）。

## トレードオフ

- サービス側で共通ルールの改善を思いついた場合、その場で編集できず「共通リポで編集 → 順輸入」の
  一手間が要る。solo 運用（基盤リポにすぐ手が届く）では許容。
- guard の共起判定は fail-safe 側に過剰遮断する（例: 共通所有ファイルを cp で別所へ複製する読み出し用途も
  ブロックされ得る）。回避は cat 等の読取コマンドで足りるため許容。

## 復活条件

チーム化して「サービス側から共通への還流」を再び回したくなったら本 ADR を見直す。旧
`backport-to-common.sh` は git 履歴（ADR-003〜005 時点の実装）から復元できる。

## 注記（2026-08-03・ADR-012）

**ADR-012 が本 ADR の一部を置き換えた。置き換わったのは「防御の主軸」であって、共通所有ファイルの
ロックそのものではない。**

- **維持**: 共通所有ファイルをプロジェクト側で編集させない決定（deny＋guard の二重封鎖・基盤リポ除外・
  封鎖対象／非対象の範囲）。ADR-010 で意味が「複製の編集禁止」→「複製を発生させない」へ移った点も
  そのまま現役。
- **変更**: 上記を支える層の位置づけ。ADR-012 は防御を3層（第1層＝コンテナ隔離／第2層＝
  `permissions.deny`／第3層＝PreToolUse フック）に再編し、**本物の境界は第1層のコンテナ隔離だけ**と
  規定した。本 ADR が主防御として頼っていた `guard-dangerous.sh`（第3層）と `permissions.deny`（第2層）は、
  「敵対的コードに対する防御」ではなく**「不注意による事故の防止」**へ格下げされる。
- 併せて `guard-shim.sh` は廃止、`guard-dangerous.sh` は deny で書ける判定を `permissions.deny` へ移して
  縮小する。脅威モデルも「不注意」から「実行時に生成され、レビューも信頼もできない任意のコード」へ更新。
- 隔離境界の具体は ADR-013。
