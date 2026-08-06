# ADR-011: CI を Reusable Workflow + Composite Action の三層構成に統一する

- 日付: 2026-08-03
- ステータス: 採用

## 背景

CI の方式が 2 つ並存し、生成物と既存プロジェクトで食い違っていた。

| | `profiles/_base` | `service-templates/` |
|---|---|---|
| 方式 | devcontainer + make（3ジョブ） | composite action（6ジョブ） |
| 利用者 | `new-service.sh` で今生成されるもの | 既存2プロジェクト |
| stack-gates | 実装済み | 全て `echo "TODO"` |

`new-service.sh` は `service-templates/` を 1 バイトも読まないが、`audit-consistency.sh` 検査(10)が `profiles/_base/` との diff 一致を強制しているため、二重管理コストだけが発生し続けていた。

判断軸は「ゲートの改善が全プロジェクトに伝播するか」である。プロジェクト数が増えるほど、伝播しない構成は破綻する。

## 決定

三層構成に統一する。

```
Reusable Workflow（基盤・on: workflow_call）
  ├ ゲート層  → Composite Action（基盤が実装・伝播する）
  │    req-coverage / tier-tripwire / coverage-floor / secret-scan
  └ スタック層 → make に委譲（各プロジェクトが実装する）
       lint / test / audit-deps / build
```

各プロジェクトの `.github/workflows/ci.yml` は次のみとする。

```yaml
jobs:
  ci:
    uses: gracetech-jp/ai-dev-foundation/.github/workflows/service-ci.yml@v1
    with:
      profile: product-web
      foundation-ref: v1     # uses: のタグと同じ値。省くと main が使われる（注意事項・2026-08-06）
```

`service-templates/` は廃止する。

## 理由

Composite Action と Reusable Workflow は排他ではなく抽象度が違う。前者はステップ、後者はジョブを扱う。推奨構成は reusable workflow が内部で composite action を呼ぶ形であり、これによりジョブレベルの統制とステップレベルの合成可能性の両方が得られる。

従来の composite action のみの構成では、ゲートの実装は伝播するが「どのジョブをどの順で走らせるか」「何が hard で何が soft か」は各リポジトリにコピーされたままだった。Reusable Workflow を被せることで、そこまで基盤が握れる。

スタック層を make に委譲するのは、ゴールデンパスの設計原則に従う。ゴールデンパスは全チームに同じ言語・フレームワークを要求せず、不整合が不釣り合いに大きな運用リスクを生む層に絞るべきとされる。標準化対象として挙げられるのはアイデンティティ、RBAC、プロビジョニング、デプロイパイプライン、ポリシー制御であり、言語ごとの lint ツールは含まれない。

またゴールデンパスが満たすべき性質として、任意・透明・拡張可能・カスタマイズ可能の 4 点が挙げられる。スタック別 composite action を基盤が持つと、新スタックのたびに基盤変更が必要になり後半 2 つを損なう。

この方針は ADR-010 の「スタック中立の規律」と整合する。

## 注意事項

- 本番ワークフローは `@main` ではなくタグを指す。バージョン付きにより、パイプラインを壊さずに旧版を非推奨にできる
- **`uses:` のタグと同じ ref を `foundation-ref` にも渡す**（2026-08-06 追記）。
  `github.job_workflow_sha` が空になるため、省くと共通基盤の checkout が既定ブランチへ落ち、
  **タグでピン止めしても main のコードでゲートが回る**。二重記述になるが、症状が出ないまま
  版がずれるより優先する（実測と経緯: `docs/audit/adr011-phase2-plan-20260804.md` §8-5）
- 基盤内部から composite action を参照する場合は `./.github/actions/...` の相対パス構文を使う。常に同じコミットのコードを参照するため ref 管理が不要
- 共有ワークフローのリポジトリ自体で CI を走らせ、全 composite action が意図通り動くことを検証する。既存の bats 235 ケースに reusable workflow の検証を追加する
- 組織名 `gracetech-jp` のハードコードは composite action / reusable workflow の仕様上回避不可。プロジェクト固有情報の混入とはみなさない
- devcontainer + make 方式は破棄しない。reusable workflow の中で devcontainer を起動して make を呼ぶことは可能。CI とローカルの一致を取るかは別途判断する
- **基盤リポジトリ自身は reusable workflow を呼ばない**（2026-08-04 決定）。「CI を統一する」と決めた ADR で
  基盤だけが別方式になるため、理由を残す。reusable workflow の中身は
  **①共通基盤とプロジェクトの側置きチェックアウト ②プロジェクト側のランタイム導入 ③`projects/<name>` での make 実行**
  であり、基盤にはこの3つがいずれも当てはまらない——**基盤は側置きの「共通側」そのもの**で、
  自分を自分の配下へ置くことはできず、言語ランタイムも持たない。
  無理に通すと `github.job_workflow_sha` が自分自身を指す自己参照になり、ref 解決だけが複雑化する。
  **統一の対象は「サービスリポジトリの CI」であり、基盤の CI（配布物の dogfood）は別種のもの**である。
  ただし共有ワークフローが壊れていないことの検証は必要なので、そこは
  `common/scripts/run-gates.sh` の bats と、GitHub 上での selftest 実行で担保する
- **CI では devcontainer をビルドしない**（2026-08-04 決定）。毎 push のイメージビルドが重く、
  2026-07-23 に8ジョブ→3ジョブへ統合した理由がそのまま残る。加えて既存2プロジェクトの
  devcontainer は共通基盤を `${localWorkspaceFolder}/../..` から bind するローカル開発用設定で、
  **CI の単独 checkout では bind 元が無く起動しない**（静的サイト側が実際にこれで bare 実行へ移行済み）。
  環境一致は「CI とローカルが**同じ make ターゲット**を呼ぶ」ことで担保する

## 結果

- `service-templates/`（23ファイル）を削除する
- `audit-consistency.sh` 検査(10)の後半（`service-templates/` ↔ `profiles/_base/` の diff 強制）を削除する
- `.github/workflows/service-ci.yml` を新設する
- 既存2プロジェクトの CI を差し替える
- **バージョンは `v2` を新設し、`v1` は残す**（2026-08-04 決定 → **2026-08-06 に実測で裏づけ済み**）。
  タグを動かすと移行途中のプロジェクトが意図しないタイミングで切り替わり、段階的移行と両立しない。
  加えて `v1`（`0906ac0`）の tree には **`service-ci.yml` も `common/scripts/run-gates.sh` も無く**、
  そもそも移行先として成立しない。`foundation-ref` を明示する運用（上記）では、タグが
  「reusable の定義」と「checkout される共通基盤のコード」の**両方**を決めるため、
  動くタグの危険はさらに大きい。**v2 を切る前に手順10（配布雛形の reusable 化）を済ませること**
  （古い形の雛形が v2 に含まれると生成物と食い違う）
- **差し替えには前提条件がある**（2026-08-04）:
  - 静的サイト側 … **先に Makefile へスタックゲートを実装し、TODO 契約の `exit 3` を消す**。
    未実装のまま `make lint` / `make test` 経由へ切り替えると、CI が TODO と判定して soft 化し、
    **今まで hard だったゲートが弱体化する**
  - 動的アプリ側 … **devcontainer の compose 化の完了を待つ**。Makefile の docker 呼び出しが全面的に
    書き換わるため、CI の移行を先行させると二重の変更が衝突する。それまで現行 CI を維持する
- `profiles/_base/.github/workflows/ci.yml` を reusable workflow 呼び出しに置き換える
- ADR-003 / ADR-005 に続き、CI 方式に関する過去の分岐を解消する

## 検証（2026-08-06 に完了）

reusable workflow を GitHub 上で実行しての検証は `.github/workflows/service-ci-selftest.yml`
（`workflow_dispatch` 限定・常設）で行う。**5回実行して測定項目をすべて閉じた**（計画書 §8-1〜§8-7）。
  - **チェック名は `<呼び出し側のジョブ id> / <reusable 側のジョブ名>`** と確定
    （実測: `selftest / gates`）。雛形どおり `ci:` で呼べば `ci / gates` になる
  - **skip されたジョブも check run は作られ、conclusion が `skipped` になる**（永久ペンディングにはならない）
  - **第2回（修正後）は全ジョブ緑**。側置きチェックアウトが成立し、composite action が
    workspace 直下の `common/scripts/` を読んでゲートを実行した。`@main` の解決先は
    API の `referenced_workflows[].sha` で確定（`fa24bdc…`＝dispatch 時の main の HEAD）
  - **`job_workflow_sha` は空だった**（第3回・実測。annotation 経由で確認）。
    **設計の前提が崩れている**——未指定時に checkout が既定ブランチへ落ちるため、
    タグでピン止めしても共通基盤は `main` が使われる＝**バージョン固定が無効化される**。
    しかもゲートは緑になるので症状が出ない
  - **代替文脈も無い**（第4回・実測）。`job_workflow_ref` も空、`workflow_ref` は
    **呼び出し側**のワークフローと ref を返すだけで共通基盤の版は分からない。
    → **`foundation-ref` の明示を確定**とし、`uses:` との一致を**検査(17)で機械強制**する
    （`common/scripts/check-foundation-ref.sh`。未指定も不一致も赤）
  - **明示すれば正しい版で成立する**（第5回・実測）。既定と違う ref（過去コミット）を渡すと
    その ref で checkout され、ゲートまで緑になった。**既定ブランチと区別できる形**で確認済み
  - **配る前に不具合を1件検出した**: App 未設定時に `token:` へ空文字が入り checkout が落ちる。
    サービス側が移行すれば全リポジトリで再現する形だった（修正済み）。
    **手順6 を「一時的な検証」ではなく常設の口として残す根拠がここで実証された**

## 未解決

**測定に由来するものは残っていない。以下はすべて実施待ちの作業。**

1. **既存2プロジェクトの移行**（手順7・9）。前提条件は結果節のとおり——
   静的サイト側は Makefile のスタックゲート実装、動的アプリ側は devcontainer の compose 化
2. **手順11・12**: `service-templates/` と composite action 3本の撤去。**1 の完了が前提**
   （両プロジェクトが composite action を参照しなくなるまで消せない）
3. **ブランチ保護の設定**（`docs/audit/branch-protection-20260806.md`）。
   PAT に `Administration` を渡していないため、画面での操作を人が行う。
   基盤・HP の2本が対象で、`sumai-desk` は PR でテストが走らないため保留（同 §5-1）
4. （運用に影響しない未確認）`job_workflow_*` が空になる条件——同一リポジトリ参照か
   `workflow_dispatch` 起点か。**サービスから PR 契機で呼んだときに分かる**（1 で通る）。
   どちらであっても `foundation-ref` の明示で正しく動くため、判明したら二重記述をやめるかを
   判断すればよい（それまでは明示が必須）

**完了したもの**（2026-08-06）: 手順1〜6・10・13。
手順10 で配布雛形の CI を reusable 呼び出し（`@v2` + `foundation-ref: v2`）へ置換し、
手順13 で `v2` を `31d2a12` に切った。生成物が `@v2` を解決できることは
`new-service.sh` を1回流して確認済み（タグ実在の警告が出ないこと・`project-name` の置換・
生成直後の `make audit-all` が検査(6)(7) 込みで緑）。
