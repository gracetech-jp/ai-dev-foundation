# ADR-011 実装 フェーズ1: 調査報告

作成日: 2026-08-04 ／ 対象: `ai-dev-foundation`（branch `feature/adr-013-devcontainer-isolation`）
**リポジトリのファイルは変更していない。** 追加はこの報告書1本のみ。改善提案は書かない（フェーズ2）。

すべて実ファイルを読んで確認した。確認できなかったものは §5・§6 に「未確認」として分離した。

## 調査環境の制約（先に明示する）

| 項目 | 状態 |
|---|---|
| `gh` CLI | **この環境に無い**（`command -v gh` が空） |
| GitHub API への到達 | **不可**。`curl https://api.github.com/` は HTTP 000（ADR-013 の許可リストに `github.com` 系を入れていないため遮断される） |
| リモートの `git fetch` | **不可**（同上・SSH も遮断） |

→ **リモートに存在する v1 タグの実体、ブランチ保護、必須ステータスチェックはこの環境から確認できない。**
ローカルの git オブジェクトから分かる範囲だけを §5 に、確認手段そのものを §6 に書く。

---

## 1. 3系統の CI の突き合わせ

### 1-1. `.github/workflows/ci.yml`（基盤自身・6ジョブ）

トリガー: `push` / `pull_request`（ブランチ指定なし）。`permissions: contents: read`。
**devcontainer を使わず素の runner で `make` を直接呼ぶ。ジョブ間の `needs:` は無い。**

| ジョブ | 実行内容 | soft/hard | 失敗時に止まるもの |
|---|---|---|---|
| `audit` | `make audit-all`（`scripts/audit-consistency.sh` 14層） | hard | そのジョブのみ |
| `lint` | `make lint`（shellcheck ゼロ警告・不在は fail-closed） | hard | 同上 |
| `test` | `apt-get install bats` → `make test`（`bash -n` + bats 281ケース） | hard | 同上 |
| `req-coverage` | `make req-coverage` | hard | 同上 |
| `tier-tripwire` | `fetch-depth: 0` → `make tier-tripwire` | hard | 同上 |
| `secret-scan` | `docker run gitleaks:v8.18.4 detect --no-git --redact` | hard | 同上 |

- **soft 判定の仕組みは無い**（基盤には TODO ターゲットが無く、全て実装済みのため）。
- **集約ジョブが無い**。したがって「CI 全体の成否」を1つのチェックとして参照する口が無い。
- **`audit-consistency.sh` 検査(8)がこの6ジョブ名の実在を機械検証している**（ジョブが消えると audit が赤）。
  → **reusable workflow へ寄せてジョブ名が変わると検査(8)が落ちる。** フェーズ2で必ず同時に扱う項目。

### 1-2. `profiles/_base/.github/workflows/ci.yml`（新規生成物へ配布・3ジョブ）

トリガー・permissions は同じ。**`gates` だけ devcontainer 内で実行**（`devcontainers/ci@v0.3`、`push: never`）。

| ジョブ | 実行内容 | 失敗時に止まるもの |
|---|---|---|
| `gates` | devcontainer をビルドし、その中で `lint` → `test` → `coverage` → `audit-deps` → `req-coverage` → `tier-tripwire` を順に make 実行 | ジョブ全体（最後に `exit $fail`） |
| `audit` | 素の runner で `make audit-all` | そのジョブのみ |
| `secret-scan` | gitleaks（基盤と同一コマンド） | そのジョブのみ |

`gates` 内の soft/hard 判定（`runCmd` のシェルに直書き）:

| ゲート | 判定 | 根拠 |
|---|---|---|
| `lint` / `test` / `audit-deps` | **softable** | `is_todo()` が make の決定論的エラー行 `make: *** [...] Error 3` に一致したら `::warning::` に落として続行 |
| `coverage` | **`.coverage-floor` の値で切替** | `floor = 0` なら `make coverage \|\| ::warning::`（soft）、`floor ≠ 0` なら `run_gate coverage hard` |
| `req-coverage` / `tier-tripwire` | **常に hard** | 設定エラーの exit 2 も含め無条件 red |

`run_gate` は `fail=1` を立てるだけで継続し、最後にまとめて `exit "$fail"`（**1回の実行で全ゲートの結果が出る**）。
`gates` のみ `fetch-depth: 0`（tier-tripwire の差分基準）。

**ADR-012/013 の実装による変化**: このファイル自体は未変更。ただし配布物の中身が変わったため、
`audit` ジョブが呼ぶ `make audit-all` の内容が**検査(4)まで → 検査(5)まで**に増えている（§7）。

### 1-3. `service-templates/.github/workflows/ci.yml`（未配布・6ジョブ）

`new-service.sh` はこのディレクトリを1バイトも読まない。**現に生成されるのは 1-2 の方式**。

| ジョブ | 実行内容 | 状態 |
|---|---|---|
| `stack-gates` | lint / test / 依存監査 が全て `echo "TODO: …"` | プレースホルダ |
| `req-coverage` | `gracetech-jp/ai-dev-foundation/.github/actions/req-coverage@v1` | 実働 |
| `tier-tripwire` | 同 `tier-tripwire@v1`（`fetch-depth: 0`・`sensitive-paths: ""`） | 実働（空設定なので `.tier-tripwire-none` が無ければ exit 2） |
| `coverage-floor` | `pct=0` を固定出力 → `coverage-floor@v1` | 計測未実装のプレースホルダ |
| `audit` | `bash scripts/audit-consistency.sh` | 実働 |
| `secret-scan` | gitleaks | 実働 |

`env: FOUNDATION_REF: v1` が定義されているが、**どのステップからも参照されていない**
（`uses:` に `@v1` が直書きされている）。ファイル冒頭に「CI はこのリポジトリを単独で checkout する。
**make は使えない**（Makefile が共通基盤のマーカーを要求して fail-closed で止まるため）」と明記されている。

### 1-4. 3系統の対比（同じゲートがどう実行されるか）

| ゲート | 基盤(1-1) | 配布 `_base`(1-2) | `service-templates`(1-3) |
|---|---|---|---|
| lint | `make lint`（bare） | `make lint`（devcontainer・softable） | `echo TODO`（bare） |
| test | `make test`（bare・bats 導入） | `make test`（devcontainer・softable） | `echo TODO`（bare） |
| coverage | 無し（アプリコード無し） | `make coverage`（floor で soft/hard 切替） | composite action（`pct=0` 固定） |
| audit-deps | 無し（依存無し） | `make audit-deps`（softable） | `echo TODO` |
| req-coverage | `make req-coverage`（bare） | `make req-coverage`（devcontainer・hard） | **composite action**（bare） |
| tier-tripwire | `make tier-tripwire`（bare） | `make tier-tripwire`（devcontainer・hard） | **composite action**（bare） |
| audit-all | `make audit-all`（bare） | `make audit-all`（bare） | `bash scripts/…`（bare） |
| secret-scan | gitleaks（bare） | gitleaks（bare） | gitleaks（bare） |

**同じゲートが3通りの呼ばれ方をしている**（make 直/ make in devcontainer / composite action）。
これが ADR-011 が解こうとしている分岐そのものである。

---

## 2. `.github/actions/` の composite action 3本

### 2-1. 入力・出力・実体

| action | 入力 | 既定 | 出力 | 実体 |
|---|---|---|---|---|
| `req-coverage` | `test-paths`(**必須**) / `req-marker-re` / `adv-marker-re` / `project-root` | 後2つは `""`、root は `${{ github.workspace }}` | **無し**（終了コードのみ） | 同梱 `check-requirements-coverage.sh` を `$GITHUB_ACTION_PATH` から実行 |
| `tier-tripwire` | `sensitive-paths` / `sensitive-symbols` / `self-re` / `project-root` | 前3つは `""` | 無し | 同梱 `check-tier-tripwire.sh` |
| `coverage-floor` | `measured`(**必須**) / `project-root` | root のみ既定 | 無し | 同梱 `check-coverage.sh` |

- 3本とも `runs: using: composite` のシングルステップ（`shell: bash`）。
- 入力は **env 経由**でスクリプトへ渡す（`REQ_TEST_PATHS` / `TIER_TRIPWIRE_PATHS` 等）。
  `coverage-floor` だけ位置引数（`measured` `project-root`）。
- **3本とも出力（`outputs:`）を持たない。** 結果は終了コードだけで、
  「何件カバーされたか」のような値を後段ジョブへ渡す口は無い。
- `tier-tripwire` の action.yml に「呼び出し側は `actions/checkout` に `fetch-depth: 0` を指定すること」と
  コメントがあるが、**action 側で強制する手段は無い**（composite action は checkout の設定に介入できない）。

### 2-2. `common/scripts/` との同期状況

実測（`diff -q`）: **3対ともバイト単位で完全一致**。

```
common/scripts/check-requirements-coverage.sh ↔ .github/actions/req-coverage/check-requirements-coverage.sh
common/scripts/check-tier-tripwire.sh         ↔ .github/actions/tier-tripwire/check-tier-tripwire.sh
common/scripts/check-coverage.sh              ↔ .github/actions/coverage-floor/check-coverage.sh
```

複製が必要な理由は action.yml のコメントに明記されている——
**`$GITHUB_ACTION_PATH` から実行するため同梱が必須**（共通リポの追加 checkout もトークンも不要にする設計）。

### 2-3. 検査(10) `MIGRATION_PAIRS` による強制

`scripts/audit-consistency.sh` の `MIGRATION_PAIRS` は「正本:複製」の対を持ち、
各対について **(a) 正本の実在 (b) 複製の実在 (c) `diff -q` 一致**の3つを検査する。
1つでも欠ければ `report`（赤）。現在の登録:

```
common/docker/Dockerfile.base                 : profiles/_base/.devcontainer/Dockerfile
common/docker/init-firewall.sh                : profiles/_base/.devcontainer/init-firewall.sh
common/docker/init-firewall.sh                : .devcontainer/init-firewall.sh
common/scripts/check-requirements-coverage.sh : .github/actions/req-coverage/check-requirements-coverage.sh
common/scripts/check-tier-tripwire.sh         : .github/actions/tier-tripwire/check-tier-tripwire.sh
common/scripts/check-coverage.sh              : .github/actions/coverage-floor/check-coverage.sh
```

**注意**: 検査(10)の後半（`service-templates/` ↔ `profiles/_base/` の全ファイル diff 強制）は別ロジックで、
`NEW_FORM_RE`（`Makefile` / `.devcontainer/devcontainer.json` / `.github/workflows/ci.yml` / `claude/settings.json`）
の4件だけを「意図的に異なる」として除外している。**ADR-011 の結果節はこの後半の削除を予定している。**

---

## 3. reusable workflow で表現する必要があるもの

現在 `_base` の `ci.yml` が**ジョブ内に直書きで持っている**ものを、呼び出し側から見えなくするには
何を reusable workflow 側へ移す必要があるか。事実の洗い出しのみ（設計はフェーズ2）。

### 3-1. devcontainer ビルドと、その中での make 実行

現状は `gates` ジョブが `devcontainers/ci@v0.3` を `push: never` で使い、`runCmd` に**シェルスクリプトを直書き**している。

移す際に**呼び出し側から与える必要がある入力**（現状は暗黙に決まっているもの）:

| 項目 | 現状の決まり方 | reusable 化で必要になるもの |
|---|---|---|
| devcontainer の場所 | `devcontainers/ci` の既定（`.devcontainer/`） | 既定のままでよい。ただし compose 方式（product-web）と単体 Dockerfile 方式（product-static）で**ビルド対象が変わる**（実測: product-web のみ `dockerComposeFile` を持つ） |
| ビルドの要否 | 常にビルドする | 「devcontainer を使う/使わない」の切替。基盤自身は bare 実行、既存2プロジェクトも bare 実行（§4） |
| `fetch-depth` | `gates` のみ `0` | tier-tripwire を含むかどうかで決まる |

**devcontainer 内で make を呼ぶ形をそのまま reusable workflow へ移すと、
「呼び出し側リポジトリの devcontainer をビルドする」ことになる。** これは
`devcontainers/ci` が checkout 済みワークスペースを対象にするため成立するが、
**§4 のとおり既存2プロジェクトはどちらも devcontainer を CI で使っていない**
（静的サイト側は「CI の単独 checkout では bind 元が無くコンテナ起動に失敗する」と明記して bare へ移行済み）。

### 3-2. soft/hard の判定ロジック

現在 `runCmd` の中にある実体は次の3つ。**いずれも YAML ではなくシェルで表現されている。**

| 要素 | 実装 | reusable 化で問題になる点 |
|---|---|---|
| `is_todo()` | `make: *** [...] Error 3` への正規表現一致 | GNU make がレシピ失敗時に exit を 2 へ正規化するため、**exit code では判別できない**。出力文字列に依存する設計であり、reusable workflow の step 単位（`continue-on-error`）では表現できない。シェルのままなら移設可能 |
| `run_gate <target> <hard\|softable>` | 出力を保持しつつ `fail=1` を立てて継続 | GitHub Actions の step は「失敗＝即中断」か「`continue-on-error`＝結果を無視」の二択。**「失敗を記録して続行し、最後にまとめて落とす」はシェル側でしか書けない**（現に1ジョブに集約されている理由） |
| `coverage` の floor 切替 | `cat .coverage-floor` の値で分岐 | 呼び出し側リポジトリのファイル内容による**実行時分岐**。`with:` の入力では表現できず、workflow 内で読む必要がある |

**要点**: soft/hard の判定は**呼び出し側リポジトリのファイル内容と make の出力**に依存する。
`with:` で渡す静的な入力には落ちない。reusable workflow へ移す場合、
このシェルブロックごと reusable 側へ持っていく（＝ジョブの中身を基盤が握る）ことになる。

### 3-3. プロファイル別の差異（実測）

| 項目 | product-web | product-static | `_base`（雛形単体） |
|---|---|---|---|
| devcontainer 方式 | **compose**（`dockerComposeFile`・app + postgres） | 単体 Dockerfile | 単体 Dockerfile |
| Makefile の実装済みターゲット | `test` `lint` `coverage` `audit-deps` `audit-all` | `test` `lint` **`build`** `coverage` `audit-deps` `audit-all` | すべて `exit 3`（TODO） |
| `build` ターゲット | **無い** | **ある** | 無い |
| 生成直後の CI 期待値 | full-red（テスト0件で pytest exit 5、tripwire exit 2） | display-green（`.tier-tripwire-none` 同梱・jq で skip 判定） | — |
| プロファイル名の所在 | `.service-profile`（`product-web`） | `.service-profile` | 無し |

- **`build` の有無が非対称**。ADR-011 の決定はスタック層に `lint / test / audit-deps / build` を挙げているが、
  現在 `_base` の CI は `build` を**呼んでいない**（`gates` の列挙は lint/test/coverage/audit-deps/req-coverage/tier-tripwire）。
- **`.service-profile` が生成物に配られている**ため、呼び出し側が `with: profile:` を書かなくても
  ファイルから読める状態にはなっている（現在どこからも読まれていない）。

---

## 4. 既存2プロジェクトの CI の現状

### 4-1. 静的サイト側プロジェクトの `ci.yml`（138行・6ジョブ）

| ジョブ | 実行方式 | 内容 |
|---|---|---|
| `stack-gates` | **bare**（`pnpm/action-setup` + `setup-node@24`） | `coverage-floor@v1` を先に呼び（floor=0 なら `continue-on-error`）、続いて `pnpm install --frozen-lockfile` → lint（hard）→ test（hard）→ `pnpm audit`（soft・warning） |
| `req-coverage` | bare | `req-coverage@v1`（`test-paths: "tests src"`） |
| `tier-tripwire` | bare（`fetch-depth: 0`） | `tier-tripwire@v1`（`sensitive-paths: "functions/*"`・`self-re: '^Makefile$'`） |
| `audit` | bare | `bash scripts/audit-consistency.sh`（**make を経由しない**） |
| `secret-scan` | bare | gitleaks v8.18.4 |
| **`display-green`** | bare・`needs: [5ジョブ]`・`if: always()` | `needs.*.result` を検査し `success`/`skipped` 以外があれば赤。**「ブランチ保護はこの1本を必須にする」とコメントに明記** |

**基盤の想定との乖離**:
- 方式は `service-templates`（composite action）**寄り**だが同一ではない。`stack-gates` は TODO ではなく実装済み。
- **`display-green` 集約ジョブは基盤のどの雛形にも存在しない**（このプロジェクト独自）。
- devcontainer を CI で使わない理由がコメントに明記されている——
  「hp の devcontainer.json は foundation を `${localWorkspaceFolder}/../..` から bind するローカル開発用設定で、
  **CI の単独 checkout では bind 元が無くコンテナ起動に失敗する**」。
  → **ADR-011 が devcontainer 方式を reusable に載せる場合、この制約に正面からぶつかる。**
- make を経由しない理由も明記——「Makefile の `COMMON_ROOT` ガードが単独 checkout で fail-closed になるため」。

### 4-2. 動的アプリ側プロジェクトの `ci.yml`（77行・4ジョブ）

| ジョブ | 実行方式 | 内容 |
|---|---|---|
| `req-coverage` | bare | `req-coverage@v1`（`test-paths: "backend/tests frontend/app frontend/components frontend/lib"`） |
| `tier-tripwire` | bare（`fetch-depth: 0`） | `tier-tripwire@v1`（機微パス5件・機微シンボル9件・`self-re: '^Makefile$'`） |
| `secret-scan` | bare | gitleaks |
| `migration-import-guard` | bare（`setup-python@3.12`） | `python backend/scripts/audit_migration_imports.py`（このプロジェクト固有の不変条件） |

- 冒頭に「**スタック依存のゲート（test / lint / coverage / 依存監査 / 整合性）は `deploy.yml` が正**」と明記。
  つまり ci.yml は**共通ゲート専用**で、スタックゲートは別ファイルにある。
- **集約ジョブは無い。**
- 旧構成が `.github/workflows/ci.yml.bak` に退避されている旨の記述あり（現物の有無は未確認・`projects/` は git 管理外）。

### 4-3. 動的アプリ側プロジェクトの `deploy.yml`（342行・9ジョブ）

トリガー: `push: branches: [main]` と `workflow_dispatch`。

| ジョブ | 内容 | 備考 |
|---|---|---|
| `test-backend` | Python 3.12 + pytest | |
| `test-frontend` | Node + テスト | |
| `typecheck-frontend` | tsc + lint | |
| `lint-backend` | matrix（ruff / mypy / bandit） | |
| `audit-dependencies` | 依存監査（本番依存のみブロッキング） | |
| `consistency` | `bash scripts/audit-consistency.sh` + `python scripts/audit_structural.py` | |
| `migration-check` | **`services: postgres:16-alpine`** を立てて `alembic upgrade head` → `alembic check` | DB が要る |
| `build` | `needs: [上記7]`・`if: workflow_dispatch` のみ | クラウド認証 → コンテナレジストリへ push |
| `deploy-production` | `needs: build`・`environment: production`（手動承認）・SSH で本番ホストへデプロイ | |

**今回の対象に入るかの判断材料**:
- `deploy.yml` は**スタックゲート（test/lint/audit/consistency/migration）とデプロイが1ファイルに同居**している。
  前半7ジョブは ADR-011 の言う「スタック層」に相当し、後半2ジョブはデプロイで**ADR-011 の三層構成に該当する層が無い**。
- `migration-check` は `services:` を要求する。**現在の `_base` の `gates`（devcontainer 1ジョブ）には
  `services:` を足す口が無い**（`_base` ci.yml のコメントにも「drift 検査に DB が要るなら services: ブロックを足すこと」と
  将来対応として書かれている）。
- デプロイはクラウド認証情報・SSH 鍵・`environment: production` の承認を伴う。
  ADR-011 の決定・結果節は**デプロイに一言も触れていない**。

---

## 5. `@v1` タグの現状

| 問い | 結果 |
|---|---|
| ローカルに v1 タグが存在するか | **存在する**（ローカルタグは v1 の1本のみ） |
| v1 が指すコミット | `0906ac0`（2026-07-26 10:01:35 +0000）「feat(foundation): 雛形とユーザースコープ配布を参照方式に合わせる（フェーズ1）」 |
| v1 は main の祖先か | **祖先である** |
| v1 の `.github/actions/` と現在の HEAD の差 | **差分あり（2ファイル・5行）** |
| **リモートの v1 がローカルの v1 と同じか** | **未確認**（`gh` 無し・`git fetch` 遮断） |

差分の中身（`git diff v1 HEAD -- .github/actions/`）は**コメント中の旧ファイル名（2026-07-30 に `PROJECT.md` へ改名したもの）の追随のみ**で、
検査ロジックの変更は含まれない。

```
.github/actions/req-coverage/check-requirements-coverage.sh | 4 ++--
.github/actions/tier-tripwire/check-tier-tripwire.sh        | 6 +++---
```

**したがって「既存2プロジェクトが `@v1` で参照している実装」と「現在の基盤の実装」は、
ロジック上は一致している**（ローカルの v1 が正しくリモートを反映している場合に限る）。

**未確認の残り**: リモートの v1 タグの有無・指すコミット・`main` との関係。
ホスト側で確認する場合のコマンド: `git ls-remote --tags origin` または `gh api repos/gracetech-jp/ai-dev-foundation/git/refs/tags`。

---

## 6. ブランチ保護と必須ステータスチェック

**未確認。この環境からは原理的に確認できない。**

- `gh` CLI がインストールされていない
- GitHub API への外向き通信が ADR-013 のファイアウォールで遮断されている（`api.github.com` → HTTP 000）
- リポジトリ設定はローカルの git オブジェクトには含まれない

分かっている**間接的な事実**:

| 事実 | 出典 |
|---|---|
| 基盤の CI には集約ジョブが無く、6ジョブが並列。ジョブ間の `needs:` も無い | `.github/workflows/ci.yml` を実読 |
| 静的サイト側は集約ジョブ `display-green` を持ち、コメントに「ブランチ保護はこの1本を必須にする」「ジョブ名 display-green は固定（改名しない）」と明記 | 同 ci.yml 121-138行 |
| 動的アプリ側には集約ジョブが無い | 同 ci.yml を実読 |
| 前回の棚卸し（2026-08-03）でも「ブランチ保護設定・必須ステータスチェックの有無」は未確認事項として残っている | `docs/audit/inventory-20260803.md` §「未確認事項」 |

**確認するにはホスト側で次のいずれかを実行する必要がある**（コンテナ内からは不可）:

```
gh api repos/gracetech-jp/ai-dev-foundation/branches/main/protection
gh api repos/gracetech-jp/<project>/branches/main/protection
```

---

## 7. ADR-012/013 で追加された検査・テストの CI 対応表

| # | 資産 | 何を検証するか | 基盤 CI から呼ばれるか | 配布 CI から呼ばれるか |
|---|---|---|---|---|
| 1 | 検査(13) 隔離境界の退化検出 | Dockerfile の境界要素4種・`NOPASSWD:ALL` の再発・compose の cap_add・`bypassPermissions` と `ask` の `mcp__*` の対・**共通 `.claude` のユーザースコープ・マウント** | ✅ `audit` ジョブ（`make audit-all`） | ❌（基盤側の雛形を検査するものなので配布不要） |
| 2 | 検査(14) 二重化の突合 | 第2層 deny ↔ 第3層フックの片側欠落、`DENY_CORE` の実在、マーカーと対応表の突合 | ✅ `audit` ジョブ | ❌（配布側は別実装＝下記6） |
| 3 | `tests/init-firewall.bats`（11ケース） | ファイアウォールの fail-closed・引数拒否・非 root 拒否・追加リストの書式検査・検証の両側性 | ✅ `test` ジョブ（`make test` → bats） | ❌ |
| 4 | `tests/dist-guardrails.bats`（11ケース） | **生成物に対して**配布側の検査(5)が動くこと（deny 欠落・フック複製の再発・マウント消失・共通側マーカー消失） | ✅ `test` ジョブ | ❌ |
| 5 | `tests/audit-consistency.bats` 追加7ケース | 検査(13)(14)の赤ケース | ✅ `test` ジョブ | ❌ |
| 6 | 配布側 検査(5) ガードレール二重化の突合 | 生成プロジェクトの deny 実在・フック定義/複製の再発・マウント・共通側マーカー | ❌（基盤には無い層） | ✅ `audit` ジョブ（`make audit-all` → 配布 `audit-consistency.sh`） |
| 7 | `scripts/verify-isolation.sh`（9項目） | コンテナ内で**実際に遮断されるか**（適用スタンプ + 実通信） | ❌ **CI から呼ばれない**（コンテナ内実行が前提・Rebuild のたびに人間が流す） | ❌ 未配布 |
| 8 | `scripts/verify-guardrails.md`（7項目） | deny が**実際に発火するか**（人間が叩く） | ❌ **CI から呼ばれない**（機械化不能と結論済み） | ✅ **配布される**が実行は人間（`profiles/_base/scripts/verify-guardrails.md`） |
| 9 | R-003（許可ドメイン） | tier-tripwire の paths 経由 | ✅ `tier-tripwire` ジョブ | ✅ `gates` の `tier-tripwire`（プロジェクト固有設定に依存） |
| 10 | R-001 改訂（EARS・8項目） | req-coverage のマーカー経由 | ✅ `req-coverage` ジョブ | ✅ `gates` の `req-coverage` |

**reusable workflow へ移す際に落ちやすい箇所（事実として）**:

- **7・8 は CI に載っていない。** 載せられない理由も確定している（7 はコンテナ内実行が前提、
  8 は Claude Code のツール層を通す必要がある）。reusable workflow を作っても**この2つは CI で担保されない**。
- **1・2・6 はすべて `make audit-all` の中にある。** reusable workflow 側が `make audit-all` を呼ぶ限り自動的に載る。
  逆に「audit をスクリプト直実行に変える」（静的サイト側が実際にそうしている）と、
  **呼ばれるのは配布側の `audit-consistency.sh` のみ**で結果は同じ。
- **3・4・5 は `make test`（bats）に依存する。** bats は基盤 CI が `apt-get install` で入れている。
  reusable workflow が bare runner で `make test` を呼ぶ場合、**bats の導入ステップを持ち越す必要がある**
  （devcontainer 方式なら Dockerfile が入れているため不要）。
- **検査(8) が基盤 CI の6ジョブ名を機械検証している**（§1-1）。基盤自身の CI を reusable 化して
  ジョブ名が変わると、**検査(8)が赤になる**。

---

## 付録: 実行して確認した事実

| 確認内容 | 結果 |
|---|---|
| `diff` 3対（`common/scripts/` ↔ `.github/actions/*/`） | 3対ともバイト一致 |
| `command -v gh` | 出力なし（未インストール） |
| `curl https://api.github.com/` | HTTP 000（遮断） |
| `git tag -l` | `v1` の1本のみ |
| `git log -1 v1` | `0906ac0`・2026-07-26 |
| `git merge-base --is-ancestor v1 main` | 真（v1 は main の祖先） |
| `git diff --stat v1 HEAD -- .github/actions/` | 2ファイル・5行（コメントのみ） |
| `projects/*/.github/workflows/` の一覧 | 静的サイト側: `ci.yml` / 動的アプリ側: `ci.yml` `deploy.yml` |
| 各ワークフローの行数 | 静的 ci 138 / 動的 ci 77 / 動的 deploy 342 |
| プロファイルの devcontainer 方式 | product-web のみ compose 方式 |
| プロファイルの Makefile ターゲット | product-static のみ `build` を持つ |

**未確認事項（この環境では確認不能）**
- リモートの `v1` タグの実体、`main` との関係
- ブランチ保護・必須ステータスチェックの設定（両プロジェクトと基盤の3リポジトリ分）
- 各リポジトリの Settings → Actions → General → Access の設定
  （private リポジトリの composite action 解決に必須。動的アプリ側の ci.yml には「**未検証**」と明記されている）
- CI の直近実行結果（成功しているのか、そもそも走っているのか）
- 動的アプリ側の `ci.yml.bak` の現存（`projects/` は git 管理外のため履歴から追えない）
