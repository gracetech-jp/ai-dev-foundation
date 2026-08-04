# ADR: 新規サービス構築シェルのプロファイル基盤化

- **種別**: Architecture Decision Record / 設計仕様書
- **対象リポ**: ai-dev-foundation（共通リポ）
- **ステータス**: 承認済み（2026-07-22 大澤 将平 承認）／**v2改訂 2026-07-22**（事業形態×技術形態の2軸へ再設計。`static-site`/`web-app` → `product-static`/`product-web`。フェーズ1・2は実装済み、フェーズ3で `product-web` 実装＋リネーム）
- **作成日**: 2026-07-22
- **決定者**: 大澤 将平

---

## 1. 背景と課題

`scripts/new-service.sh` は現状、位置引数1つ（サービス名）のみを受け、分岐のない直列コピーで「スタック非依存の素の雛形」を生成する。生成物のスタック具体化（Dockerfile への Node 追記、Makefile のコマンド実装など）と CI 緑化は、すべて生成後の手作業に委ねられている。

このため、静的サイト（HP/LP）を作るたびに、また動的 Web アプリを作るたびに、同じ緑化作業を毎回繰り返す必要がある。目標は「シェルを叩いた直後に、スタックが決まり土台が動く状態で、設計→実装→テストに集中できる」こと。

## 2. 決定

新規サービス生成に **プロファイル**という第一級概念を導入する。シェルは `--profile` でサービス種別を受け取り、`_base`（共通の素の雛形）の上にプロファイル固有の断片を重ねて配布する。

### 2.1 分類軸（v2で再設計: 事業形態 × 技術形態）

プロファイルは **2軸マトリクス**で分類する。

- **事業形態軸（自社プロダクト / 受託）**: この軸が「スタックを固定できるか」を決める。自社プロダクトはスタックを*自分で決められる*ので固定してよい。受託は顧客要望に依存し*固定できない*。
- **技術形態軸（静的 / 動的）**: 静的サイト（HP/LP）か動的Webアプリか。

|  | 静的 | 動的 |
|---|---|---|
| **自社プロダクト** | `product-static` | `product-web` |
| **受託** | （将来）`contract-static` | （将来）`contract-web` |

### 2.2 今回作るのは自社の2象限のみ

受託系（`contract-*`）は、実際に案件が発生した時点で足す（「穴を先に空けない」原則）。現時点で必要なのは自社プロダクトの2つ。

| プロファイル | 対象 | スタック | 初期状態 |
|---|---|---|---|
| `product-static` | 自社の HP / LP | Astro SSG（Node 24 / pnpm 10）+ Cloudflare Pages Functions | `display-green` |
| `product-web` | 自社の動的アプリ | Python/FastAPI + PostgreSQL（compose別コンテナ）| `full-red` |

> **v2改訂の経緯**: 当初は技術形態のみの `static-site` / `web-app` で始めた。しかし `web-app` に FastAPI/PostgreSQL を焼こうとした際、「受託案件では顧客要望で Python も PostgreSQL も使わない可能性がある」ことに直面。原因は、スタックを固定できる自社プロダクトと、固定できない受託を、`web-app` という1つの箱に押し込んでいたこと。事業形態軸を足すことで、自社（固定してよい）と受託（固定しない）を分離し、両立させた。フェーズ2で作った `static-site` は `product-static` にリネームする。

## 3. 不変条件（最重要・違反禁止）

このリポの根幹原則を、プロファイル導入にあたり再確認・明文化する。共通リポには **2種類の独立した原則**が存在し、混同してはならない。

### 3.1 ドメイン不変条件（絶対に緩めない）

共通リポおよび全プロファイルは、**サービス固有のドメイン語を一切含まない**。
禁止語の例: `tenant` / `RLS` / `billing` / `Stripe` / `名寄せ` など、特定サービスの業務概念。

**危険地帯 — `product-web` プロファイル**:
- PostgreSQL・Python/FastAPI を土台として入れるのは**スタック**であり許容（OK）。これは「自社プロダクトは全部この構成でいく」と自分で決められるから焼ける。
- RLS ポリシー、テナント概念、マイグレーションのドメイン雛形を入れるのは**ドメイン**であり禁止（NG）。
- `product-web` プロファイルは「FastAPI + PostgreSQL が起動しビルド/テストが回る土台」まで。そこにドメイン構造を含めた瞬間、それは共通プロファイルではなく特定サービス専用の金型になる。

> なぜ自社プロダクトは Python/PostgreSQL を焼けて、受託は焼けないのか: 自社プロダクトのスタックは*自分で決める*ので固定できる（`product-web`）。受託のスタックは*顧客が決める*ので固定できない（将来の `contract-web` はスタックゼロ・full-red だけを配る想定）。この非対称性が、事業形態で軸を割った理由。

> 判定ルール: 「その語・その構造は、別業種の別サービスでもそのまま使えるか？」使えなければドメイン＝プロファイルに入れてはいけない。

### 3.2 スタック非依存原則（今回、意図的に再定義する）

従来「メカニズム本体は言語・ビルドツール固有のコマンドを持たない」としてきた。この原則は**メカニズム本体（`new-service.sh`、CI の `ci.yml`、gate スクリプト群）については維持**する。

一方で、**プロファイル層はスタック依存物を持ってよい**。プロファイルの存在意義がスタック具体化だからである。ただしプロファイルが持ってよいのはスタック依存物のみ（3.1 のドメインは持たない）。

整理:

| 対象 | スタック依存物 | ドメイン語 |
|---|---|---|
| メカニズム本体（シェル/CI/gate） | 持たない | 持たない |
| プロファイル層 | **持ってよい** | 持たない |

### 3.3 プロファイルの階層的位置づけ

- プロファイルは「新規サービスを生成する仕組み」の一部＝**メカニズム**であり、共通リポに置いてよい。
- ただしプロファイルの中身（Dockerfile 断片等）は「メカニズムが配布するテンプレート素材」であって、共通リポの CI がそのプロファイル自身の実行結果をテストするわけではない。この階層を混同しない。

## 4. ディレクトリ構造

```
ai-dev-foundation/
  profiles/
    _base/                    # 全プロファイル共通（現行の素の雛形に相当）
    product-static/
      profile.manifest        # 何を追加/置換するかの宣言
      files/                  # 追加・置換するファイル実体
        .devcontainer/Dockerfile      # Node/pnpm 入り（_base を置換）
        Makefile                      # test/lint/audit-deps を pnpm で実装済み（置換）
        ...
    product-web/
      profile.manifest
      files/
        .devcontainer/Dockerfile      # Python/uv 入り（_base を置換）
        Makefile                      # pytest 等で実装済み（置換）
        compose.yaml                  # PostgreSQL を別コンテナで起動（§7.1）
        ...
  scripts/
    new-service.sh            # --profile を受ける
```

> 将来 `contract-static` / `contract-web` を足す際も同じ `profiles/<name>/` 構造に従う。

## 5. 合成方式（決定: ファイル追加＋置換方式）

### 5.1 アルゴリズム

1. `_base/` を生成先へ展開する。
2. 指定された `profiles/<name>/` の `profile.manifest` を読む。
3. manifest の指示に従い、`profiles/<name>/files/` 内のファイルを生成先へコピーする。
   - `add`: 生成先に無いファイルを追加。
   - `replace`: 生成先の同名ファイルを丸ごと差し替える。
4. 従来どおり `SERVICE_NAME` のプレースホルダ置換を行う。

置換は `cp` の重ね掛けで完結する。マーカー挿入・部分パッチは行わない（デバッグ容易性・シェル本体の非肥大化を優先）。

### 5.2 `profile.manifest` スキーマ（案）

```
# profile.manifest — product-static（# で行/行末コメント可）
profile: product-static
description: Astro SSG + Cloudflare Pages Functions
failclosed_profile: display-green   # full-red | display-green の2種のみ（§7.2）
# 以降は 1行1ファイル: <op> <path>。op ∈ {add, replace}
replace .devcontainer/Dockerfile
replace Makefile
add .tier-tripwire-none
```

> 補足（フェーズ1実装で確定）: 当初案のネストYAML（`files:` 配下の `- path:`/`op:`）は、このリポの行指向マニフェスト作法（当時の `.backport-manifest` 等がすべて「1行1エントリ＋#コメント」。同ファイルは 2026-07-30 の順輸入廃止・ADR-010 で削除済み）に揃え、`<op> <path>` の1行形式へ平坦化した。bashパーサが数行で済み、シェル肥大化を避けられる。`failclosed_profile` キーはフェーズ1メカニズムでは未消費で、フェーズ2で各プロファイルの初期状態実現に用いる。

シェルは manifest を解釈するだけにとどめ、ロジックを manifest 側へ寄せる（シェル本体を薄く保つ）。

## 6. シェルインターフェース（決定: `--profile` 必須化）

```
./scripts/new-service.sh <サービス名> --profile product-static
./scripts/new-service.sh <サービス名> --profile product-web
```

- `--profile` を**必須**とする。未指定はエラーで exit 1 とし、利用可能プロファイル一覧を表示する。
- 目的: 新規サービス生成時の「種別分類し忘れ」を機械的に防ぐ。
- **決定: 素の雛形の単体生成は許さない。** `_base` は合成の内部部品としてのみ存在し、`--profile _base` のような明示指定の経路は設けない。分類を徹底し、「とりあえず素で」という分類回避の誘惑を構造的に排除する。将来まだ分類できない種別が出た場合は、その時点で新プロファイルを足す（穴を先に空けておかない）。
- 選択可能な `--profile` の値は、実在するプロファイル（現時点は `product-static` / `product-web`）のみ。将来 `contract-static` / `contract-web` を足しうる。
- 既存のバリデーション（サービス名の正規表現、生成先の既存チェック）は維持する。

## 7. fail-closed の初期状態（プロファイル別）

雛形は本来 fail-closed（実装するまで CI が赤）設計。プロファイルごとに初期の厳格さを変える。

| プロファイル | 初期状態 | 根拠 |
|---|---|---|
| `product-static` | **表示部分は緑スタート**（`display-green`）| 表示主体でロジックが薄く、初手赤の安全網の価値が低い。req-coverage の env デフォルト設定・`.tier-tripwire-none` 同梱・coverage 0床で、生成直後から表示部分の CI が緑。 |
| `product-web` | **fail-closed 維持**（`full-red`）| ビジネスロジックが重く、実装強制の安全網に価値がある。ゲートは実コマンドで実装するが、生成直後は空プロジェクトのため自然に赤になる（例: pytest はテスト0件で exit 5＝テストを書くまで赤／`.tier-tripwire-none` を配らないので tier-tripwire は exit 2＝機微定義を強制）。TODO+exit 1 の「偽の赤」ではなく、実判定の結果としての赤。lint 等が実コード上クリーンで緑になるのは正当な実判定であり許容する（test/coverage/tier-tripwire が確実に赤なので実装強制は保たれる）。 |

**重要（`product-static` でも機微は締める）**: `product-static` が緑スタートなのは**表示部分のみ**。Pages Functions のような外部公開・個人情報を扱う部分は、サービス構築後に要件化し tripwire 対象に含めることで締め直す（本 ADR のスコープ外＝各サービス側作業。§9 参照）。プロファイルは「緑スタートの土台」を配るが、機微を緩めるものではない。

### 7.2 `failclosed_profile` の値（決定: 2種のみ）

manifest の `failclosed_profile` キーが取りうる値は、次の**2種に限定**する。all-green・custom は設けない。

| 値 | 意味 | 対象 |
|---|---|---|
| `full-red` | 全ゲート赤スタート。実装するまで CI は赤。 | `product-web`（ロジックが重く、実装強制の安全網に価値がある）。将来の `contract-web` も同じ。|
| `display-green` | 表示・ビルド系は緑、機微部分は赤。 | `product-static`（表示主体、機微はフォーム等に限局。機微が無いLP単発も実質これで包含）|

**all-green（全ゲート緑スタート）を入れない理由**: fail-closed を根本から抜き、本基盤の背骨「LLMの自己申告を単独で信頼しない」「空虚な緑を潰す」（要件トレーサビリティADR）と正面衝突する。「軽いから」「単発だから」という例外はなし崩しに広がる。LP単発は `display-green` が包含するため、専用の全緑パターンは不要。

**custom（manifestで任意にゲート組み合わせを指定）を入れない理由**: 無数の初期状態が生まれ把握不能になり、「シンプルなメカニズム」原則に反する。fail-closed の初期状態は離散的な少数パターンに限る。2種で表現できない本物のケースが将来出たら、その時点で3つ目の**名前付き**パターンを足す。「何でもあり」の器は先に作らない（`--profile _base` を許さなかったのと同じ判断＝逃げ道を先に空けない）。

### 7.1 `product-web` のデータベース構成（決定: 別コンテナ）

`product-web` プロファイルの開発環境では、**PostgreSQL をアプリと同一コンテナに同居させず、compose で別コンテナとして立てる**。

- 理由: 本番環境はアプリとデータベースが分離されているのが通常であり、開発環境をその構造に近づけることで「開発では動いたが本番で嵌る」ズレを減らす。とりわけデータ分離の挙動（マルチテナント等）は本番構造でこそ検証価値が高く、開発と本番の構造差が最も痛い箇所で表面化するのを防ぐ。
- ドメイン境界の注意: プロファイルが用意するのは「PostgreSQL が別コンテナで起動し、アプリから接続できる土台」まで。スキーマ・マイグレーション・テナント/RLS 等のドメイン構造は含めない（§3.1）。
- 適用範囲: これは**自社プロダクト**（`product-web`）が PostgreSQL を標準採用すると決めているから焼ける構成。将来の受託（`contract-web`）は DB を顧客要望に委ねるため、compose も PostgreSQL も**配らない**（スタックゼロ・full-red のみ）。

## 8. 共通リポ側 実装タスク（このADRのスコープ）

| # | タスク | 内容 |
|---|---|---|
| C-1 | `profiles/_base/` 整備 | 現行の素の雛形を `_base` として切り出す |
| C-2 | `profiles/product-static/`（フェーズ2完了） | フェーズ2で `static-site` として実装済み。**v2でのリネーム（`static-site`→`product-static`）はフェーズ3に含める**（`git mv` ＋ manifest の `profile:` 値 ＋ 参照更新 ＋ bats）。中身（Node 24/pnpm 10 Dockerfile、pnpm Makefile、display-green）は不変。|
| C-3 | `profiles/product-web/` 作成 | Python/uv の Dockerfile、pytest 実装済み Makefile、`full-red` 維持、`compose.yaml`（**PostgreSQL を別コンテナ**、§7.1）、`profile.manifest`（`failclosed_profile: full-red`）。**ドメイン語を含めない**（RLS/tenant/マイグレーション雛形は禁止。PostgreSQL・FastAPI はスタックなので可）。|
| C-4 | `new-service.sh` 改修 | `--profile` 引数追加（必須化）、manifest 解釈、`_base`＋プロファイル合成、未指定エラー＋一覧表示 |
| C-5 | `profile.manifest` パーサ | manifest の add/replace を解釈する最小実装 |
| C-6 | CODEOWNERS デフォルト | プレースホルダを `gracetech-jp` ソロ運用の固定値で配布 |
| C-7 | ドキュメント更新 | `docs/rules/repo-layout.md` にプロファイル概念とディレクトリ規約を追記。`repo-layout.md:39` の「必須要素の増減時は同時更新」義務との整合を取る |
| C-8 | 自己検証 | `audit-consistency.sh` がプロファイル追加で誤検知しないか確認 |

## 9. サービス構築後タスク（各サービス側・スコープ外）

参考として明記（このADRでは実装しない）。

| # | タスク | 備考 |
|---|---|---|
| S-1 | 機微部分の要件化 | 例: HP の問い合わせフォーム（Pages Functions）を R-001 として要件登録（Tier B〜A）|
| S-2 | tripwire 対象パス指定 | 例: `TIER_TRIPWIRE_PATHS` に `functions/*` を追加し機微だけ締める |
| S-3 | `PROJECT.md` 記入 | 技術スタック欄・データストア欄を埋める |
| S-4 | デプロイ配線 | 例: Cloudflare Pages の Git 連携でビルド&デプロイ（CI は品質ゲート専念）|
| S-5 | プロダクト実装 | コンテンツ・デザイン・ロジックそのもの |

## 10. 決定事項サマリ

| 論点 | 決定 |
|---|---|
| プロファイル分類 | 2軸（事業形態 自社/受託 × 技術形態 静的/動的）。今回は自社の2つ `product-static` / `product-web`。受託は案件発生時に足す |
| 合成方式 | ファイル追加＋置換方式（マーカー挿入は不採用）|
| `--profile` | 必須化（未指定はエラー）|
| fail-closed 初期値 | `product-static`=display-green / `product-web`=full-red |
| 素の雛形の単体生成 | 許さない（`_base` は内部部品のみ、分類を徹底）|
| `product-web` の DB | compose で別コンテナ（自社は PostgreSQL 標準採用のため焼ける）|
| 受託プロファイル | スタックゼロ・full-red のみを配る想定（顧客要望に依存するため固定しない）|
| ドメイン境界 | プロファイルはスタック依存物のみ。ドメイン語（RLS/tenant等）は禁止 |
| 実装分業 | 本ADRを承認済みアーティファクトとし、実装は現物リポを読めるエージェントへ委譲 |

## 11. 未解決・実装時に判断する点

- 将来「静的だがAPIあり」等の中間種が出た際、2プロファイルを部品合成へ発展させる移行パス（本ADRでは逃げ道を残すにとどめ、実装は先送り）。
- `audit-consistency.sh` がプロファイル層をどう扱うか（誤検知回避の具体策）。

### 解決済み（本ADRで決定）

- 素の雛形の単体生成: **許さない**（`_base` は内部部品のみ、`--profile` 必須を徹底）。§6 参照。
- `product-web` の DB 構成: **compose で別コンテナ**（自社は PostgreSQL 標準採用のため焼ける）。§7.1 参照。

## 12. 次アクション

1. 本ADRを人間（大澤）が承認 → ステータスを「承認済み」に更新し Notion へ ADR 登録。
2. 承認済みADRを添えて、現物リポを読めるローカルLLM/Claude Code に C-1〜C-8 の実装を依頼。
3. 実装後、HP を `./scripts/new-service.sh <サービス名> --profile product-static` で生成し、基盤の検証を兼ねる。
