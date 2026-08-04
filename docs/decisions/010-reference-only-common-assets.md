# ADR-010: 順輸入の廃止 — 共通資産はプロジェクトへ配布せず参照させる

記録日: 2026-07-30 ／ 対象リポ: ai-dev-foundation ／ 状態: 承認済み（大澤将平・2026-07-30）・実装済み

## 背景 — 解決したかった問題

ADR-005 が定めた順輸入（`sync-from-common.sh` による pull 型配布）と ADR-009 の一方通行化により、
共通資産はプロジェクトへ**複製として配られ**、更新は各プロジェクトが取り込む形になっていた。
複製が存在することが、次の問題を構造的に生んでいた。

- **同期漏れが機能停止になる**: プロジェクト固有ルールのファイル名を `PROJECT.md` へ改名した際、
  共通所有5ファイルが旧名を参照したまま残り、`session-start-rules.sh` が存在しないファイルを
  `if [ -f ]` で握って**無言でルールを注入しない**状態になった（sumai-desk・2026-07-30）。
- **配布定義が陳腐化する**: 参照方式への移行で不要になった `check-*.sh` がマニフェストに残り、
  順輸入のたびにプロジェクトへ再配布された。プロジェクトは毎回削除し直す必要があった。
- **所有の単位と、変わる理由の単位がズレる**: 「全プロジェクト共通」の値と「この環境だけ」の値
  （例: `permissions.additionalDirectories` の絶対パス）が同じ上書き単位に同居し、共通の理由で
  上書きすると固有の値が消えた。同型の問題は HP の申し送り FI-3・FI-4 にも現れていた。
- **1つの変更が N リポの作業になる**: 共通側を直したあと、各プロジェクトで dry-run → apply →
  コミットが必要で、取り込みが遅れたプロジェクトだけ古い仕組みで動き続けた。

一方で、参照の基盤（マーカー `.ai-dev-foundation-root`・`common/make/*.mk`・`common/scripts/`・
composite action）は 2026-07-26 のフェーズ0〜2 で既に揃っており、使い切れていないだけだった。

## 決定

**共通資産の実体は共通リポに1つだけ置き、プロジェクトは実行時に参照する。配布・順輸入を廃止する。**

- `scripts/sync-from-common.sh` と `.backport-manifest` を**削除**。プロジェクト側の複製も削除。
- `new-service.sh` は共通資産（`CLAUDE.md`・`docs/rules/`・共通スクリプト）を**配らない**。
- 生成先を `$HOME/projects/` から**共通リポの `projects/` 配下**へ変更（参照解決の前提）。
- 基盤リポ自身も同じ形にする（旧 `scripts/` の複製5件を削除し `common/scripts/` を正本に一本化）。

### 参照の経路

| 共通資産 | 参照方法 |
|---|---|
| `CLAUDE.md` | Claude Code が起動位置から上位を遡って連結する |
| `docs/rules/` | `session-start-rules.sh` がマーカーを上方探索し共通側から索引を注入（解決失敗は警告注入＝fail-loud） |
| ゲート実装 | `Makefile` が `common/make/{contract,gates}.mk` を include し、`common/scripts/check-*.sh` を実行 |
| git フック | `make install-hooks` が `.git/hooks/` から `common/scripts/` へ `ln -sf` |
| CI | `.github/actions/` の composite action を `uses:` で参照（CI に共通リポは checkout されない） |

### 参照にできず複製が残るもの

- composite action の同梱スクリプト（`$GITHUB_ACTION_PATH` から読むため同梱必須）
- `profiles/_base/.devcontainer/Dockerfile`（`new-service.sh` が `_base` を読む）
- `.claude/` 骨格（Claude Code がプロジェクトルートを見る。パスが 1:1 対応しない）

これらは手動同期のまま。ずれは `audit-consistency.sh` 検査(6)(10) が機械検出する。
`.claude/` はユーザースコープ配布（`/home/node/.claude`）への移行で複製ゼロへ向かう。

## 実装上の設計判断

- **共通所有ロックは撤去せず、意味を変えた**。「配られた複製を編集させない」→
  **「複製をプロジェクト側に発生させない」**。複製が再び生えるのが最も起こりやすい退化であり、
  対象が消えてもロックの役目は残る。パス一覧は据え置き、`sync-from-common.sh`（もう存在しない
  概念）だけを外した。R-002 の negative_space も同じ趣旨に書き換えた（**保護範囲は不変**）。
- **`contract.mk` を include する形に雛形を揃えた**。既存2プロジェクトは「`all` の定義と既定ゴールが
  衝突する」ため意図的に `contract.mk` を避けていたが、雛形では include を先に置くことで
  `all` が既定ゴールになり衝突しない。
- **無言スキップになる検査を残さなかった**。監査の「マニフェスト突合」は `[ -f ... ]` で
  囲まれていたため、ファイルを消すだけでは**黙って通る検査**になる。検査ごと撤去した。
  同様に、new-service.sh の配布検査は「配っていること」から**「配っていないこと」**の検査へ反転させた。
- **順序依存の assert を潰した**。`tests/audit-consistency.bats` の「ロックの退化」検査は
  1つの glob に2語を並べており、実際には撤去した別検査のメッセージに引っ張られて通っていた。
  部分文字列ごとの検査に分割した。

## トレードオフ

- **プロジェクトは共通リポの `projects/` 配下に置かなければならない**。単独で clone しても
  `make` が即エラーになる（fail-closed）。CI が単独 checkout で動くのは composite action 経由に
  限られる。独立して clone・ビルドできる性質を捨てて、複製ゼロを取った。
- 共通側の変更が**取り込み操作なしに全プロジェクトへ即座に効く**。壊れる変更を入れると全プロジェクト
  が同時に赤になる。緩衝としての「取り込みタイミングの自由」は無くなった。基盤側の bats と
  整合性監査がその緩衝を代替する。
- ローカル固有の権限（`additionalDirectories` 等）は `.claude/settings.local.json` に置く運用が
  前提になる（共通所有の `settings.json` に書くと `.claude/` 手動同期で消える）。

## 復活条件

プロジェクトを共通リポの外へ出す必要が生じたら（別組織への引き渡し・OSS 化・単独 CI が必須に
なった等）本 ADR を見直す。旧 `sync-from-common.sh` と `.backport-manifest` は git 履歴
（ADR-009 時点の実装）から復元できる。

## 置き換えた ADR

- **ADR-003**（逆輸入モデル）・**ADR-005**（順輸入 pull 型）: 配布そのものを廃止したため失効。
- **ADR-009**（一方通行配布）: 「一方通行」の前提だった配布が無くなった。ロックに関する決定
  （deny＋guard の二重封鎖・基盤リポ除外・例外範囲）は本 ADR でも有効。

## 注記（2026-08-03・ADR-011）

**ADR-011（CI の三層構成）が本 ADR の「スタック中立の規律」を継承している。** 本 ADR で共通資産を
参照方式に寄せた際、共通側が握るのは「仕組み」であって「スタック固有の実装」ではない、という線引きを
置いた。ADR-011 はこの線引きを CI に適用し、ゲート層（req-coverage / tier-tripwire / coverage-floor /
secret-scan）は基盤が composite action で実装して伝播させ、スタック層（lint / test / audit-deps / build）は
各プロジェクトの `make` へ委譲する構成にしている。スタック別の composite action を基盤に持たせない
判断も同じ規律から出ている（新スタックのたびに基盤変更が要る構成は、拡張可能・カスタマイズ可能を損なう）。

また本 ADR が手動同期の担保として残した `audit-consistency.sh` 検査(10)のうち、
`service-templates/` ↔ `profiles/_base/` の diff 強制は、ADR-011 の `service-templates/` 廃止で
不要になる（実装は未了）。

## 注記（2026-08-04・ADR-013）— 雛形の追随漏れを解消した

**本 ADR の参照方式に、`profiles/_base/.devcontainer/devcontainer.json` だけが追随できていなかった。**
既存2プロジェクト（grace-tech-hp・sumai-desk）は 2026-07-26 のフェーズ2でマウントを参照方式へ
書き換えていたが、雛形は「単独プロジェクトを `/workspace` に置く」移行前の形のまま残っていた。
このため、当時の雛形から生成したプロジェクトは共通の `CLAUDE.md` / `docs/` / マーカーが見えず、
**生成直後には参照方式が成立しない**状態だった（2026-08-03 の棚卸しで検出）。

ADR-013 の実装（2026-08-04）で、雛形と product-web の compose を既存2プロジェクトと同じ
位置関係（`/workspaces/foundation/projects/<名前>` ＋ 共通側を readonly）へ揃えた。
以後は雛形が参照方式の正しい形を持つ。

この追随漏れが2週間気づかれなかったのは、**雛形の devcontainer.json を検査する仕組みが無かった**ため。
ADR-013 で追加した検査(13)は隔離境界の要素を見るもので、マウントの位置関係そのものは今も
機械検査していない（生成物を実際に起動しないと検証できないため）。
