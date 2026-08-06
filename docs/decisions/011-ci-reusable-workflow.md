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
- **バージョンは `v2` を新設し、`v1` は残す**（2026-08-04 決定）。タグを動かすと移行途中のプロジェクトが
  意図しないタイミングで切り替わり、段階的移行と両立しない。旧版は非推奨として残す（注意事項1点目に従う）
- **差し替えには前提条件がある**（2026-08-04）:
  - 静的サイト側 … **先に Makefile へスタックゲートを実装し、TODO 契約の `exit 3` を消す**。
    未実装のまま `make lint` / `make test` 経由へ切り替えると、CI が TODO と判定して soft 化し、
    **今まで hard だったゲートが弱体化する**
  - 動的アプリ側 … **devcontainer の compose 化の完了を待つ**。Makefile の docker 呼び出しが全面的に
    書き換わるため、CI の移行を先行させると二重の変更が衝突する。それまで現行 CI を維持する
- `profiles/_base/.github/workflows/ci.yml` を reusable workflow 呼び出しに置き換える
- ADR-003 / ADR-005 に続き、CI 方式に関する過去の分岐を解消する

## 未解決

- ~~ブランチ保護と必須ステータスチェックの設定状況が未確認~~ → **2026-08-06: 設定内容を確定して提示済み**
  （`docs/audit/branch-protection-20260806.md`）。**設定作業そのものは未実施**——コンテナへ渡している
  PAT に `Administration` を渡していないため、画面での操作を人が行う。
  基盤リポは「main 直 push を許すか」を決めないと必須チェックを入れられない（同ファイル §5）。
- reusable workflow を GitHub 上で実行しての検証は `.github/workflows/service-ci-selftest.yml`
  （`workflow_dispatch` 限定・2026-08-06 追加）で行う。**未実行**。
  これで確定させるのは「reusable 経由のチェック名」「`job_workflow_sha` の解決先」
  「skip されたジョブの conclusion」の3点（フェーズ2計画 §8 の 4・7・8）
