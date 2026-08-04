# ai-dev-foundation 棚卸し（2026-08-03）

調査対象: `/workspace`（branch `main` / HEAD `d579a28`）
変更は一切行っていない。生成スクリプトの実行だけは `NEW_SERVICE_PROJECTS_ROOT` をスクラッチパッドへ向けて実施し、リポジトリには何も書いていない。

作業ツリーの状態: `.claude/settings.json` のみ変更あり（差分は `"theme": "dark"` → `"auto"` の1行だけ）。

---

## 1. リポジトリ構造

追跡ファイル総数: **139**。

```
ai-dev-foundation/
├── .ai-dev-foundation-root     # 参照解決の起点マーカー（空ファイル・0バイト）
├── CLAUDE.md                   # 共通ルール正本。各プロジェクトは上位ディレクトリ探索で読む
├── Makefile                    # 基盤自身の品質ゲート入口（test/lint/audit-all/req-coverage/tier-tripwire）
├── README.md                   # 直下ツリーと主要コマンド（所在の正本）
├── .editorconfig               # TAB / UTF-8 / LF
├── .gitignore                  # `.claude/*` の選択的追跡と `/projects/` の除外
├── .req-coverage-baseline      # 未カバー要件の猶予リスト（実体は全行コメント＝登録0件）
├── .tier-tripwire-allow        # トリップワイヤ例外 allowlist（同上・登録0件）
│
├── common/                     # 参照方式で各プロジェクトが実行時に参照する共通資産の実体
│   ├── make/                   #   contract.mk（ターゲット契約・install-hooks）/ gates.mk（ゲート呼び出し）
│   ├── scripts/                #   ゲート実装3本 + git フック2本 + resolve-common.sh
│   └── docker/                 #   Dockerfile.base（devcontainer ベースイメージの正本）
│
├── docs/
│   ├── rules/                  # 全プロジェクト共通ルール11本（正本。session-start が索引だけ注入）
│   ├── requirements/           # 基盤自身の要件（R-001 / R-002 の2件）
│   ├── decisions/              # ADR 10本 + テンプレ運用ガイド
│   ├── service-rules/          # 基盤リポ固有ルール（consistency.md 1本）
│   └── audit/                  # 過去の棚卸し記録（inventory-20260724.md 1本）
│
├── profiles/                   # 新規プロジェクト生成の雛形（new-service.sh が実際に読む唯一の場所）
│   ├── _base/                  #   全プロファイル共通骨格
│   ├── product-static/         #   Astro SSG + Cloudflare Pages（display-green）
│   └── product-web/            #   FastAPI + PostgreSQL（full-red）
│
├── projects/                   # 生成先。git 管理外（.gitignore で /projects/）。現在 grace-tech-hp / sumai-desk
├── scripts/                    # 基盤リポ自身の運用スクリプト（new-service.sh / audit-consistency.sh）
├── service-templates/          # 「参照方式版の配布雛形」。現状 new-service.sh からは一切読まれない（→ §7）
├── tests/                      # bats 回帰テスト6ファイル・235ケース
│
├── .claude/                    # 基盤リポ自身のガードレール（settings.json / scripts / skills / agents）
├── .devcontainer/              # 基盤リポ自身の開発環境
├── .github/
│   ├── workflows/ci.yml        #   基盤リポ自身の CI（6ジョブ）
│   └── actions/                #   各プロジェクトが `uses:` で参照する composite action 3本
└── .vscode/                    # 空ディレクトリ（git 未追跡・中身なし。→ §7）
```

---

## 2. 雛形の中身（実際に生成して確認）

`scripts/new-service.sh <名前> --profile <名前>` を両プロファイルで実行し、生成後のツリーを列挙した（両方 exit 0）。
`--profile` は必須で、`_base` の単体指定は拒否される。生成先は `$ROOT/projects/<名前>` 固定（テスト用に `NEW_SERVICE_PROJECTS_ROOT` で差し替え可能）。

### 2.1 両プロファイル共通で生成されるもic（27ファイル）

| パス | 由来 | 備考 |
|---|---|---|
| `.claude/settings.json` | `_base` → プロファイルが replace | allow/deny は共通、`ask` のみプロファイル別 |
| `.claude/scripts/guard-dangerous.sh` | `_base` | root の `.claude/` と完全同一（監査(6)が diff 強制） |
| `.claude/scripts/session-start-rules.sh` | `_base` | 同上 |
| `.claude/agents/consistency-auditor.md` | `_base` | |
| `.claude/agents/security-reviewer.md` | `_base` | |
| `.claude/skills/extract-requirements/SKILL.md` | `_base` | |
| `.claude/skills/verify-request/SKILL.md` | `_base` | |
| `.devcontainer/Dockerfile` | プロファイルが replace | |
| `.devcontainer/devcontainer.json` | `_base`（product-web は replace） | |
| `.devcontainer/postCreate.sh` | `_base` | `.env` 生成 + `make install-hooks` |
| `.editorconfig` | `_base` | |
| `.env.example` | `_base`（product-web は replace） | |
| `.github/workflows/ci.yml` | `_base` | devcontainer + make 方式の3ジョブ |
| `.gitignore` | `_base/gitignore.template` | |
| `.coverage-floor` | `_base` | 中身は `0` |
| `.req-coverage-baseline` | `_base` | 全行コメント（登録0） |
| `.tier-tripwire-allow` | `_base` | 全行コメント（登録0） |
| `.service-profile` | プロファイルが add | プロファイル名1行 |
| `Makefile` | プロファイルが replace | |
| `PROJECT.md` | `_base/PROJECT.md.template` | `[サービス名]` を置換 |
| `README.md` | `_base/README.md.template` | `SERVICE_NAME` を置換 |
| `docs/decisions/README.md` | `_base` | ADR 運用ガイド |
| `docs/decisions/000-template.md` | `_base` | ADR テンプレ |
| `docs/requirements/README.md` | `_base` | 要件運用ガイド（一覧表は空行） |
| `docs/requirements/R-000-template.md` | `_base` | 要件テンプレ（`status: draft`） |
| `docs/requirements/INVARIANTS-template.md` | `_base` | negative space テンプレ |
| `docs/service-rules/consistency.md` | `_base` | 【要記入】8箇所の記入用雛形 |
| `scripts/audit-consistency.sh` | `_base` | 検査(1)(2)(3) は TODO コメントのみ |

`mkdir` はするが最終的に空のまま残るディレクトリ: なし（`docs/requirements`・`docs/service-rules`・`docs/decisions`・`scripts` は全て中身が入る）。

**配布されないもの（設計どおり・ADR-010）**: `CLAUDE.md`、`docs/rules/`、`common/scripts/` の共通スクリプト（`pre-push`・`commit-msg`・`check-*.sh`）、`common/make/*.mk`。すべて基盤リポ側の実体をマーカー上方探索で参照する。

### 2.2 product-web 固有（追加4ファイル・合計31）

- `.devcontainer/compose.yaml` … app + postgres:18 の2コンテナ。DB は空で起動（スキーマ・マイグレーション・初期化SQLは配らない）
- `.python-version` … `3.14`
- `pyproject.toml` … fastapi / uvicorn / sqlalchemy / psycopg、dev に pytest / coverage / ruff
- `app/main.py` … `/health` で `SELECT 1` を打つだけの参照実装
- 置換されるもの: `.devcontainer/Dockerfile`、`.devcontainer/devcontainer.json`（compose 方式）、`Makefile`、`.claude/settings.json`、`.env.example`

Makefile は全ターゲットが実コマンド（`uv run pytest` / `uv run ruff check .` / `uv run coverage` / `pip-audit`）。TODO スタブは無く、生成直後は「テスト0件で pytest が exit 5」「tier-tripwire が機微未定義で exit 2」により自然に赤になる（`full-red`）。

### 2.3 product-static 固有（追加2ファイル・合計29）

- `docs/requirements/.tier-tripwire-none` … 「機微面なし」宣言。これがあるため tier-tripwire は正当スキップして緑
- 置換されるもの: `.devcontainer/Dockerfile`、`Makefile`、`.claude/settings.json`

Makefile は `package.json` の有無と `scripts.test/lint/build` の定義有無を `jq` で見て、無ければ警告 echo で skip（`display-green`）。`coverage` は `COVERAGE_MEASURED=0` を固定で渡し、floor=0 と比較して緑。

### 2.4 生成後に**存在しない**もの（工程を語る上で重要）

- `tests/` ディレクトリそのものが生成されない。両プロファイルの Makefile は `REQ_TEST_PATHS := tests`（static は `tests src`）を指すが、`check-requirements-coverage.sh` は `[ -e "$p" ] || continue` でスキップするため、要件0件なら緑のまま通る。
- テストファイルの雛形（サンプルテスト・adversarial テストの雛形）は1つも無い。
- `docs/README.md`（生成物側）は無い。`repo-layout.md` は「下位を案内する階層に README を置く」と規定しているが、生成物の `docs/` には README が無く、これを検査するゲートも配布側には無い。
- `CHANGELOG` / リリース手順 / deploy ワークフローは無い。
- `.github/actions/` は配布されない（各プロジェクトは `uses: gracetech-jp/ai-dev-foundation/.github/actions/...@v1` でリモート参照する想定だが、**生成される `_base` の ci.yml はそれを使わず make 方式**。→ §7）

---

## 3. 工程ごとの現状

### 3.1 要件定義

**ルール**
- `docs/rules/requirements.md` … 配置・採番（`R-<連番>-<スラッグ>.md`）、front-matter スキーマ、批准レス運用、要件↔テスト紐づけ、negative space、adversarial 生成規約
- `docs/rules/tiers.md` … 4軸最大値方式の S/A/B/C 判定と Tier 別厳格度表
- `CLAUDE.md`「📝 ドキュメント」節 … 「要件の正本は `docs/requirements/`」「テストを緑にする目的で要件側を動かすことは禁止」
- スキル `extract-requirements`（**配布される**） … 既存仕様から R-id を起こす手順
- `session-start-rules.sh` が毎セッション「要件件数 ratified/draft」と要件取扱いの原則1文をコンテキストへ注入

**成果物の雛形**
- `docs/requirements/README.md`（運用ガイド＋空の要件一覧表）
- `docs/requirements/R-000-template.md`（front-matter + 受け入れ基準 + 記入要点コメント）
- `docs/requirements/INVARIANTS-template.md`（negative space と adversarial テスト対応表）
- product-static のみ `docs/requirements/.tier-tripwire-none`

**機械ゲート**
- `common/scripts/check-requirements-coverage.sh` … 未カバー要件（S/A即赤・B/C はベースライン猶予）、dangling マーカー、negative_space 有りで adversarial 無し（G4）、ベースラインへの S/A 登録禁止（B3）
- `common/scripts/check-tier-tripwire.sh` … 機微パス／シンボルの変更に ratified Tier-S 要件があるかの裏取り（F2）、機微 test/fixture も対象（F3）、要件0件時の静的走査警告（S4）、未定義は exit 2
- `common/scripts/pre-push` の3段目・4段目
- CI: 基盤は `req-coverage` / `tier-tripwire` の独立ジョブ、配布 `_base` ci.yml は `gates` ジョブ内で hard 実行
- `.github/actions/req-coverage` / `tier-tripwire`（composite action。既存プロジェクトが使用中）

### 3.2 設計

**ルール**
- `docs/decisions/README.md` … 1決定1ファイル、連番の削除・再利用禁止、置換時はステータス更新して本文は書き換えない
- `CLAUDE.md` … 「新機能追加時は `docs/` 配下に仕様書（設計メモ）を作成する。ただし仕様書は要件の正本ではない」
- `docs/rules/code-style.md`「モジュール構成」節（一般論）

**成果物の雛形**
- `docs/decisions/000-template.md`（日付/ステータス/背景/決定/理由/注意事項/結果）
- `docs/decisions/README.md`（運用ルール）
- 設計メモ・仕様書そのものの雛形は**なし**（`docs/` 直下に置けとあるが空欄テンプレは無い）

**機械ゲート**
- **なし**。ADR の存在・更新・ステータス整合を検査するスクリプトは基盤側にも配布側にも無い。
- 基盤の `audit-consistency.sh` (1) は `docs/` 内の `docs/rules/*.md` 参照リンク切れを見るが、これは設計工程のゲートではなくドキュメント参照の検査。
- サブエージェント `consistency-auditor` の description に「設計ドキュメントのハルシネーション」検証が挙がっているが、これは LLM 実行であって機械ゲートではない。

### 3.3 実装

**ルール**
- `docs/rules/code-style.md`（インデント・命名・型・リンタ・モジュール構成）
- `docs/rules/security.md`（秘密情報・入力バリデーション・出力・依存・AIエージェントのガードレール・静的検査の防御ライン）
- `docs/rules/token-efficiency.md`
- `CLAUDE.md`「⚠️ Claude Codeへの制約（MUST）」（削除確認・本番コマンド承認・破壊的git禁止・コミットは明示指示後のみ・push は自ら実行しない）
- サブエージェント `security-reviewer`（配布される）

**成果物の雛形**
- product-web: `app/main.py`（FastAPI 最小 + DB疎通）、`pyproject.toml`、`compose.yaml`
- product-static: アプリ雛形は**なし**（`package.json` すら生成されず、Makefile が「Astroプロジェクト未作成」として skip する前提）

**機械ゲート**
- `make lint`（product-web は `ruff check .`、product-static は `pnpm run lint` が定義されていれば実行、`_base` は exit 3 の TODO）
- `.claude/scripts/guard-dangerous.sh`（PreToolUse フック。→ §5）
- `.claude/settings.json` の `permissions` deny/ask
- `common/scripts/commit-msg`（Conventional Commits の機械強制）
- CI `secret-scan`（gitleaks v8.18.4 を docker で実行）
- `make audit-deps`（product-web は `pip-audit`、static は lockfile 有りなら `pnpm audit --audit-level=high`）

### 3.4 テスト

**ルール**
- `docs/rules/testing.md`（基本ルール・カバレッジ目標・テスト名・方針・要件トレーサビリティのマーカー規約）
- `docs/rules/tiers.md` の厳格度表（S/A は adversarial 必須）
- `docs/rules/requirements.md` §6（adversarial は実装と別コンテキストでの生成を推奨）
- `CLAUDE.md`「🧪 テスト」（新機能は実装と同時に作成／バグ修正は再現テスト先行／ビジネスロジック80%・API 100%）

**成果物の雛形**
- **なし**。テストファイルの雛形は1つも配布されない。`tests/` ディレクトリも生成されない。
- 関連する設定だけは配布される: `.coverage-floor`（初期値 `0`）、Makefile の `REQ_TEST_PATHS` / `REQ_MARKER_RE` / `ADV_MARKER_RE`

**機械ゲート**
- `make test`（product-web は `uv run pytest`＝テスト0件なら exit 5 で赤、static は package.json 依存で skip、`_base` は exit 3）
- `make coverage` → `common/scripts/check-coverage.sh`（`.coverage-floor` との一方向ラチェット。floor 引き上げは手動）
- `req-coverage` の adversarial 必須判定（G4）
- `tier-tripwire` の機微 test/fixture 判定（F3）
- 基盤自身は `bats tests/` 235ケース（`make test` で `bash -n` 構文検査と合わせて実行）

### 3.5 リリース

**ルール**
- `docs/rules/git.md`「開発フェーズと main 直接 push」… MVP フェーズ中は main 直 push を例外的に許可。切替条件の1つが「本番相当環境への初回リリース」
- `docs/rules/quality-gates.md` §4 に一文だけ「build / deploy は全ジョブの成功を前提にする」
- `CLAUDE.md`「本番環境に影響するコマンドは実行前に提示して承認を得る」
- バージョニング・タグ付け・変更履歴・リリースノート・ロールバック手順のルールは**なし**

**成果物の雛形**
- **なし**。deploy ワークフロー、`CHANGELOG.md`、リリースチェックリスト、いずれも配布されない。
  （`projects/sumai-desk/.github/workflows/deploy.yml` は存在するが、これはそのプロジェクトが独自に作ったもので基盤の雛形ではない）

**機械ゲート**
- **なし**。基盤にも配布雛形にもリリースに関わるジョブは無い。

### 3.6 保守運用

**ルール**
- `docs/rules/consistency.md`（変更後チェックリスト・監査スクリプトの3層構成・実行タイミングの二重化・作業完了の定義）
- `docs/rules/common-assets.md`（共通資産の所有と参照・手動同期が残るもの・スタック中立の規律）
- `CLAUDE.md`「整合性監査を定期的に実施する」「AIが同じ間違いを繰り返した場合、原因と理由を該当ルールファイルに1行追記する」
- スキル `audit-ai-rules`（**基盤リポのみ。配布対象外として `FOUNDATION_ONLY` に明示登録**）
- サブエージェント `consistency-auditor`（配布される）
- 監視・ログ設計・アラート・インシデント対応・オンコール・バックアップ・障害復旧のルールは**なし**（全リポジトリ横断 grep で該当語のヒット0）

**成果物の雛形**
- `docs/service-rules/consistency.md`（層構成表・実コマンド表・リネーム台帳が【要記入】8箇所）
- `scripts/audit-consistency.sh`（検査(1)(2)(3) は TODO コメントのみ、(4) リネーム残渣スキャンだけ空配列で動作）
- ランブック・障害対応手順・運用ドキュメントの雛形は**なし**

**機械ゲート**
- `make audit-all`（基盤側は12層の実装済み検査、配布側は実質(4)のみ）
- `common/scripts/pre-push` 1段目
- CI の `audit` ジョブ

---

## 4. CI の全体像

CI ワークフローは3系統ある。**基盤自身**・**生成物に配布されるもの**・**service-templates 側（未配布）**。

### 4.1 `.github/workflows/ci.yml`（基盤リポ自身・6ジョブ）

トリガーは全ジョブ共通で `push` と `pull_request`（ブランチ指定なし）。`permissions: contents: read`。devcontainer を使わず素の ubuntu-latest 上で make を直接呼ぶ。

| ジョブ | 実行内容 | 失敗時に止まるもの |
|---|---|---|
| `audit` | `make audit-all` → `scripts/audit-consistency.sh`（12層） | このジョブのみ。他ジョブとの依存関係は定義されていないため並行実行され、他は止まらない |
| `lint` | `make lint` → shellcheck（対象は配布シェル資産11パターン。shellcheck 不在は fail-closed） | 同上 |
| `test` | `apt-get install bats` → `make test`（`bash -n` 構文検査 + `bats tests/` 235ケース） | 同上 |
| `req-coverage` | `make req-coverage`（`REQ_TEST_PATHS=tests`、マーカー `@req:` / `@adversarial:`） | 同上 |
| `tier-tripwire` | `fetch-depth: 0` で checkout → `make tier-tripwire`（機微パス7 glob、シンボルは空） | 同上 |
| `secret-scan` | `docker run gitleaks:v8.18.4 detect --source=/repo --no-git --redact` | 同上 |

ジョブ間に `needs:` は無く、必須チェック設定（ブランチ保護）もリポジトリ側の状態としては未確認。したがって「失敗時に何が止まるか」は **CI 上は当該ジョブの赤表示のみ**で、マージやプッシュを機械的に止める配線はこのファイルには無い。実質的な阻止は `pre-push` フック側にある。

`audit-consistency.sh` 検査(8)が、この6ジョブ名の実在を機械検証している（ジョブが消えると audit が赤になる）。

### 4.2 `profiles/_base/.github/workflows/ci.yml`（**新規生成物に配布される**・3ジョブ）

| ジョブ | 実行内容 | 失敗時に止まるもの |
|---|---|---|
| `gates` | `devcontainers/ci@v0.3` でコンテナをビルドし、その中で `lint` → `test` → `coverage` → `audit-deps` → `req-coverage` → `tier-tripwire` を順に make 実行 | ジョブ全体。ただし soft/hard の区別あり（下記） |
| `audit` | 素の runner で `make audit-all` | このジョブのみ |
| `secret-scan` | gitleaks v8.18.4 | このジョブのみ |

`gates` の fail/soft 判定:
- `lint` / `test` / `audit-deps` … **softable**。make が `Error 3` を出したら（＝Makefile 雛形の TODO ターゲットの `exit 3`）`::warning::` に落として緑。実装して exit 3 を消した瞬間に自動で red 化する
- `coverage` … `.coverage-floor` が `0` の間は soft、`0` 以外になった時点で hard
- `req-coverage` / `tier-tripwire` … **常に hard**。設定エラーの exit 2 も含めて無条件 red
- 各 `run_gate` は `fail=1` を立てるだけで継続するため、最後にまとめて `exit $fail`

旧8ジョブ構成を 2026-07-23 に統合した経緯がコメントに残っている（devcontainer ビルドが毎 push × 6回走るため）。

### 4.3 `service-templates/.github/workflows/ci.yml`（**配布されない**・6ジョブ）

参照方式版。make を使わず composite action を `uses:` で呼ぶ。`env: FOUNDATION_REF: v1`。

| ジョブ | 実行内容 | 状態 |
|---|---|---|
| `stack-gates` | lint / test / 依存監査 が全て `echo "TODO: ..."` | プレースホルダのまま |
| `req-coverage` | `gracetech-jp/ai-dev-foundation/.github/actions/req-coverage@v1` | 実働 |
| `tier-tripwire` | 同 `tier-tripwire@v1`（`fetch-depth: 0`。`sensitive-paths`/`symbols` は空文字） | 実働（空設定なので `.tier-tripwire-none` が無ければ exit 2） |
| `coverage-floor` | `pct=0` を固定出力してから `coverage-floor@v1` | 計測未実装のプレースホルダ |
| `audit` | `bash scripts/audit-consistency.sh` | 実働 |
| `secret-scan` | gitleaks | 実働 |

**既存の実プロジェクト2件（grace-tech-hp / sumai-desk）はこちら側の形式を使っている**（両方とも `uses: gracetech-jp/ai-dev-foundation/.github/actions/...@v1` を含む）。つまり今 `new-service.sh` で生成すると、既存2プロジェクトとは別方式の CI が入る。

### 4.4 composite action（`.github/actions/`）

| action | 入力 | 実体 |
|---|---|---|
| `req-coverage` | `test-paths`(必須) / `req-marker-re` / `adv-marker-re` / `project-root` | 同梱の `check-requirements-coverage.sh` |
| `tier-tripwire` | `sensitive-paths` / `sensitive-symbols` / `self-re` / `project-root` | 同梱の `check-tier-tripwire.sh` |
| `coverage-floor` | `measured`(必須) / `project-root` | 同梱の `check-coverage.sh` |

3本とも `common/scripts/` の同名ファイルと**バイト単位で完全一致**（`diff` で確認済み）。`$GITHUB_ACTION_PATH` から読む必要があるための意図的な複製で、ずれは `audit-consistency.sh` 検査(10)の `MIGRATION_PAIRS` が diff 強制している。

---

## 5. フック/ガードの全体像

### 5.1 `guard-dangerous.sh`（PreToolUse / Bash 専用・239行）

前処理: `jq` 不在は **exit 2 で Bash 実行自体をブロック**（fail-closed）。`tool_name != "Bash"` は素通し。検査用に引用符とバックスラッシュを除去した複製 `STRIPPED` を作る（`rm -r'f'` のような分割を潰すため）。

**A. 破壊的コマンド検査（`| ; & && ||`・改行でセグメント分割し、セグメント単位で判定）**

| # | 検知対象 | 網羅範囲 |
|---|---|---|
| 1 | `rm` の再帰＋強制 | 結合(`-rf`/`-fr`/`-Rf`)・分離(`-r -f`)・混在(`-r --force`)・パス先行(`rm dir -rf`)。位置・順序に依存しない |
| 2 | `git push --force` 系 | `--force` / `-f` / `--force-with-lease[=ref]` |
| 3 | `git reset --hard` | |
| 4 | `git clean -f` 系 | `-fd` / `-dfx` などの結合フラグ、`--force` |
| 5 | `git branch` の強制削除 | `-D`、結合フラグ、`--delete` + `--force` の併用 |
| 6 | `git checkout` による変更破棄 | `git checkout -- .` / `git checkout .` |

正規表現は GNU 拡張の `\b` を使わず POSIX 文字クラスで書かれている（BSD/macOS grep で無言に素通しするのを防ぐため）。

**B. 秘密ファイル読み取り検査（コマンド全体の共起で判定。パイプ跨ぎを塞ぐため）**

- 読み取りコマンド一覧 `READERS`: `cat less more head tail tac strings xxd hexdump od vim vi nano emacs cp scp dd base64 awk sed grep rg nl bat jq diff source xargs` に加え、インタプリタ `python[0-9]*(.[0-9]+)* node nodejs perl ruby php deno bun tsx ts-node`
- 境界条件: 直後が `/` `.` `-` なら「パス成分」とみなして不一致（`ls /home/node/.ssh/` や `find /usr/lib/python3.12/` の誤遮断を 2026-07-26 に修正）
- 検知7: `.env` 系（`.env.production.local` のような多段サフィックスも対象）。`.env.example` / `.sample` / `.template` / `.dist` は事前除去。`process.env` / `import.meta.env` / `Bun.env` / `Deno.env` は言語構文としてサニタイズし誤遮断を回避
- 検知8: 鍵・認証情報。
  - 強い指標（そのまま共起判定）: `id_rsa` / `id_ed25519` / `id_ecdsa` / `id_dsa`、`.npmrc`、`.ssh/`、`.aws/`、`.config/gcloud/`、`secrets/`、`.netrc`、`.git-credentials`、`.kube/`、`.docker/config.json`。`id_*.pub` は事前除去
  - 曖昧な拡張子（`.pem` `.key` `.p12` `.pfx`）は、直後が引用符・空白・行末のときのみ一致。`row.key` のようなプロパティアクセスとの誤判定を避けるためここだけクォート除去前の生コマンドを見る。受け入れている偽陰性として `cat a.key|base64`（空白なしパイプ）がコメントに明記されている

**C. 共通所有ファイルへの書き込み遮断（ADR-009 / ADR-010）**

発動条件: プロジェクトルート（`CLAUDE_PROJECT_DIR`、無ければ `$PWD`）に `profiles/_base/` が**無い**とき＝サービスリポ側でのみ動く。基盤リポ自身は編集元なので対象外。

対象パス `COMMON_OWNED`: `CLAUDE.md` / `docs/rules/` / `.claude/settings.json` / `.claude/scripts/{guard-dangerous,session-start-rules}.sh` / `.claude/skills/{extract-requirements,verify-request}/` / `.claude/agents/{consistency-auditor,security-reviewer}.md` / `scripts/{pre-push,commit-msg,check-coverage.sh,check-requirements-coverage.sh,check-tier-tripwire.sh}`

- (a) リダイレクト（`>` / `>>` / `>|`）先が共通所有ファイル → deny
- (b) 変更系コマンド（`tee cp mv dd install truncate patch rsync`、`sed -i`、インタプリタ全種）と共通所有パスの共起 → deny。セグメント単位で判定
- **`rm` は 2026-07-26 に対象から外されている**（参照方式への移行で各サービスが複製を削除する必要があるため。編集は引き続き遮断）。コメントに「フェーズ5で共通所有ロックごと撤去する前提」と明記
- 例外: `cp|rsync|install` の**第1引数**が `profiles/_base/` で始まる骨格同期だけ通す

**明示されている限界**（`docs/rules/security.md` §静的検査の防御ライン、R-001 の「対象外」節）: 難読化（`'.e'+'nv'`・`chr()`・base64 デコード）、ファイル実行（`python script.py`）、間接実行（`npm run` / `npx` / `uv run`）、ライブラリ経由の暗黙読み込み（`require('dotenv').config()`）。脅威モデルは「不注意」であって「悪意ある実行者」ではないと CLAUDE.md に明記されている。

### 5.2 `session-start-rules.sh`（SessionStart）

- プロジェクトルートを `CLAUDE_PROJECT_DIR` → `git rev-parse --show-toplevel` で決める
- マーカー `.ai-dev-foundation-root` を上方探索して共通リポを見つけ、`docs/rules/` の索引（H1 見出しから自動抽出）を注入。**1件も解決できなければ警告文を注入する（fail-loud）**
- `PROJECT.md` があれば全文注入
- 要件件数（ratified / draft / その他）と、draft がある場合の警告を注入
- 要件取扱いの原則1文を常設

### 5.3 `guard-shim.sh`（`service-templates/` にのみ存在・**未配布**）

`CLAUDE_PROJECT_DIR` が起動ディレクトリを指すため、サブディレクトリから `claude` を起動するとフックスクリプトが見つからず**無警告で素通しする（fail-open）**——という実測された問題を塞ぐための薄いシム。マーカーを上方探索し、見つからなければ exit 2 でブロック。委譲先が読めない場合、および実行できず 126/127 が返った場合も exit 2 に倒す。

**現状、`new-service.sh` で生成されるプロジェクトの `settings.json` は `bash "$CLAUDE_PROJECT_DIR/.claude/scripts/guard-dangerous.sh"` を直接呼んでおり、シムを経由しない。** シムが解決しようとした fail-open は生成物に残っている。

### 5.4 `permissions`（`settings.json`）

- `allow`（7件）: `git diff/log/status/add`、`make test/lint/audit-all`
- `deny`（配布側 51件 / 基盤側 37件）: 破壊的 git・rm 7件 + `Read()` による秘密ファイル 30件 + 配布側のみ ADR-009 ロック `Edit(...)` 14件
- `ask`: 基盤・`_base` は13件（主要パッケージマネージャ網羅 + `*migrate*` + `gh workflow run`）。プロファイルがスタック別に絞る（product-web は5件、product-static は5件）
- `Write(...)` の deny は 2026-07-26 に全廃されている（Claude Code のファイル権限チェックに一致せず**効かないルール**だったため）。`audit-consistency.sh` 検査(7)②が `Write(` の再混入を機械検出する

### 5.5 git フック（`common/scripts/`、`make install-hooks` が `ln -sf`）

- `pre-push` … `make audit-all` → `make test` → `make req-coverage` → `make tier-tripwire` の4段。どれか1つでも落ちれば push をブロック（回避は `--no-verify`）
- `commit-msg` … Conventional Commits の件名を正規表現で検証。`Merge` / `Revert` / `fixup!` / `squash!` は免除

---

## 6. 要件トレーサビリティの現状

### 6.1 要件はどこに、どんな形式で書かれるか

`docs/requirements/` に **1要件 = 1ファイル**、`R-<連番>-<スラッグ>.md`。YAML front-matter:

```
id: R-101              一意・不変・再利用禁止（欠番は許容）
title: <一行表題>
tier: <S|A|B|C>        tiers.md の4軸最大値方式
status: <draft|ratified>   ratified のものだけがゲート対象
ratified_by: <主体>    任意の証跡
paths:                 この要件が統べる機微コードの glob（tier-tripwire の照合キー）
negative_space:        起きてはいけないこと（S/A 必須）
```
本文に「## 受け入れ基準」。`R-000-template.md` は固定名で検証対象外（唯一の除外）。

**基盤自身の要件は2件のみ**、どちらも Tier S / ratified:
- `R-001` 破壊的操作・秘密読取の機械的遮断（paths 6件、negative_space 2件）
- `R-002` 共通所有ファイルのサービス側編集封鎖（paths 6件、negative_space 3件）

`R-002` の `ratified_by` は「LLM（ADR-009 の決定に基づき起票。draft を経ておらず、内容のユーザー確認は未実施）」と明記されている。

### 6.2 Tier 分類の実装

- 定義は `docs/rules/tiers.md`。4軸（複雑度・影響範囲・不可逆性・セキュリティ影響）の**最大値**で S/A/B/C を決める
- Tier 別の厳格度は表で規定: ID付き永続要件（S/A 必須）、negative space（S/A 必須）、adversarial テスト（S/A 必須）、未カバーゼロゲート（S/A/B 対象・C 対象外）、ベースライン免除（S/A 不可・B/C 可）
- Tier フィールド自体は LLM も書き換えられる。過小申告（デスカレーション）の防止は `tier-tripwire` の**コード実態からの裏取り**に一本化されている（旧「Tier の人間批准」は ADR-008 で廃止）

### 6.3 テストとの紐付けの検証方法

`check-requirements-coverage.sh` が行うこと（設定は Makefile が env で渡す。マーカー正規表現がスタック依存のため既定値を持たない＝未設定は exit 2）:

1. `docs/requirements/R-*.md` を走査し front-matter を検証。`id` が `R-<数字>` でない・`tier` が S/A/B/C でない・ID 重複はすべて **exit 2（fail-closed）**
2. `REQ_TEST_PATHS` 配下の全ファイルを `grep -oE "$REQ_MARKER_RE"` で走査し `R-<数字>` を抽出、被覆マップを作る。`ADV_MARKER_RE` で adversarial 被覆も別途集計。パスに空白があれば exit 2
3. `.req-coverage-baseline` の健全性（B3）: S/A の登録は exit 2、存在しない要件IDも exit 2
4. dangling 検出: マーカーが指す ID の要件が無い／`ratified` でない → 赤
5. 判定: S/A は未カバーで即赤（猶予なし）、S/A で `negative_space` があるのに adversarial マーカーが無ければ赤（G4）。B/C はベースライン登録があれば警告に緩和

基盤でのマーカー規約は `# @req: R-001` / `# @adversarial: R-001`（bats のコメント行）。

`check-tier-tripwire.sh` が行うこと:

1. `TIER_TRIPWIRE_PATHS` / `SYMBOLS` の**両方が未定義**なら exit 2。**両方が明示的に空**なら `docs/requirements/.tier-tripwire-none` の存在を要求し、あれば正当スキップ・無ければ exit 2
2. 差分基準を `TRIPWIRE_BASE` → `origin/main` → `HEAD~1` → 空ツリーの順で決定
3. 変更ファイルのうち、パス glob 一致（①）と、追加行・**削除行**の両方に対する機微シンボル一致（②）の和集合を機微変更とする（弱体化は削除で起きるため削除も対象）
4. 振り分け: `*.md`・`docs/` 配下は警告、`TIER_TRIPWIRE_SELF_RE` 一致（機微パターンの定義元ファイル）は警告、test/fixture は**警告に落とさず** ratified Tier-S 要件を要求、プロダクトコードは統べる Tier-S 要件を要求。tier<S の要件しか無ければ「申告デスカレーション」として赤
5. `.tier-tripwire-allow` に登録された glob は赤→警告に緩和（ログには残る）
6. S4: ratified Tier-S 要件が0件なのに機微パス／シンボルが存在するなら「空虚な緑の疑い」を警告（差分と無関係の静的走査）

### 6.4 このゲートは実際に機能しているか

**基盤リポでは機能している。** 実行して確認した:

```
make req-coverage   → ベースライン登録数: 0 / ✅ 未カバー要件・danglingの問題なし
make tier-tripwire  → 差分基準: origin/main / ✅ 機微変更は適切な Tier-S 要件に統べられています
make audit-all      → 12層すべて通過 ✅
make lint           → shellcheck 警告なし ✅
make test           → bash -n + bats 235ケース 全通過 ✅
```

対象ファイルの実在:
- 要件ファイル: `R-001` / `R-002` の2件が実在し、両方 ratified・Tier S
- テストマーカー: `tests/guard-dangerous.bats`（154ケース）に `@req: R-001` `@req: R-002` `@adversarial: R-001` `@adversarial: R-002`、`tests/resolve-common.bats`（12ケース）に `@req: R-001` `@adversarial: R-001`。S/A 要件2件とも被覆済み・adversarial も充足
- 機微パス: Makefile の `TIER_TRIPWIRE_PATHS` に7 glob が明示され、いずれも実在するファイルを指す。`TIER_TRIPWIRE_SYMBOLS` は意図的に空（理由が Makefile にコメントで説明されている）
- `.tier-tripwire-none` は基盤には**置かれていない**（置くと全体が正当スキップされるため、`audit-consistency.sh` 検査(8)が存在自体を赤にする）
- ベースライン・allowlist はどちらも登録0件（コメントのみ）

マーカーを持たない bats: `audit-consistency.bats`(22) / `new-service.bats`(18) / `req-coverage.bats`(13) / `tier-tripwire.bats`(16) の計69ケース。これらは要件に紐づいていないが、R-001/R-002 が既に他ファイルで被覆されているため req-coverage は緑になる。

**生成物側での実効性**:
- product-web … `TIER_TRIPWIRE_PATHS` 空・`.tier-tripwire-none` 無しなので生成直後は **exit 2 で赤**（設計どおり `full-red`）
- product-static … `.tier-tripwire-none` が同梱されるので**正当スキップして緑**。req-coverage も要件0件・`tests/` 未生成なので緑。つまり生成直後の static プロジェクトでは、このゲートは実質何も検証していない状態から始まる（`.tier-tripwire-none` のコメントに「機微を持つに至ったら締め直せ」と書かれている）

2026-07-24〜25 に基盤自身が「空設定＋機微面なし宣言」で緑になっていた実績があり、その再発防止として `audit-consistency.sh` 検査(8)（`TIER_TRIPWIRE_PATHS=""` での起動検出、`.tier-tripwire-none` の存在検出）が追加されている。

---

## 7. 死んでいるもの

### 7.1 参照されていないスクリプト/設定ファイル

**`service-templates/` ディレクトリ全体（23ファイル）**
- `scripts/new-service.sh` は `profiles/_base/` と `profiles/<name>/files/` しか読まない。`service-templates/` は生成物に1バイトも入らない
- 自身の README に「現時点では `new-service.sh` がまだ `profiles/_base/` を読むため、両方を対で維持している」と明記
- `audit-consistency.sh` 検査(10)が `profiles/_base/` との diff 一致を機械強制しているため、片方を直すともう片方も直す必要がある（二重管理コストは発生し続ける）
- 例外として `Makefile` / `.devcontainer/devcontainer.json` / `.github/workflows/ci.yml` / `claude/settings.json` の4件は「参照方式へ意図的に書き換えた」ものとして不一致が許容されている（`NEW_FORM_RE`）

**`service-templates/claude/scripts/guard-shim.sh`**
- `_base` に対応物が無く、監査の対をなす対象からも明示除外（`! -name 'guard-shim.sh'`）
- `tests/resolve-common.bats` の6ケースがこれをテストしており CI でも実行されるが、**配布経路が無いため実プロジェクトでは1度も動かない**
- §5.3 に書いたとおり、これが塞ごうとした fail-open は現在の生成物にそのまま残っている

**`common/scripts/resolve-common.sh`**
- リポジトリ全体を grep した結果、`source` している実行コードは**存在しない**。参照は `tests/resolve-common.bats`（テスト）、`common/README.md`、`docs/rules/common-assets.md`（ドキュメント）のみ
- 「共通基盤のルートを解決する唯一の起点」と自称しているが、実際にマーカー探索を行っている `profiles/_base/Makefile`・各プロファイル Makefile・`service-templates/Makefile`・`session-start-rules.sh`・`guard-shim.sh` はいずれも**探索ロジックを自前でインライン実装**している（同じ while ループが5箇所に重複）

**`.vscode/`**
- 空ディレクトリ。git 未追跡（`git ls-files .vscode` が0件）
- ルート `README.md` のツリーには「`.vscode/  # エディタ設定（ファイルネスト等）`」と記載されている

### 7.2 CI から呼ばれていないテスト

該当なし。`tests/` の6ファイル235ケースはすべて `make test` → `bats tests/` で一括実行され、基盤 CI の `test` ジョブと `pre-push` 2段目の両方から呼ばれる。

ただし前述のとおり、`guard-shim.sh` を対象とする6ケース（`tests/resolve-common.bats`）は、テスト対象そのものが配布されない資産である。

### 7.3 中身が空、またはプレースホルダのまま放置されているファイル

**設計どおりの空（放置ではない）**
- `.ai-dev-foundation-root`（0バイト。マーカーなので中身不要）
- `.req-coverage-baseline` / `.tier-tripwire-allow`（基盤・`_base`・`service-templates` の全て。「初期は空」と自己記述あり）
- `.coverage-floor` = `0`（同上）
- `profiles/_base/scripts/audit-consistency.sh` の TODO 3件、`profiles/_base/docs/service-rules/consistency.md` の【要記入】8箇所、`PROJECT.md.template` の【要記入】多数 — 各サービスが埋める記入欄として設計されている

**プレースホルダのまま**
- `service-templates/.github/workflows/ci.yml` の `stack-gates` ジョブ（lint / test / 依存監査がすべて `echo "TODO: ..."`）と `coverage-floor` ジョブ（`pct=0` 固定）。ただしこのファイル自体が未配布
- `profiles/_base/Makefile` の `test` / `lint` / `coverage` / `audit-deps`（`exit 3`）。これは CI の soft 判定と噛み合った意図的な契約であり、`_base` 単体では生成されないため実害の経路は無い

### 7.4 README 等に書いてあるが実体が無いもの

| 記載箇所 | 記載内容 | 実態 |
|---|---|---|
| `README.md` ツリー | `.vscode/  # エディタ設定（ファイルネスト等）` | ディレクトリは存在するが**空**。git 未追跡 |
| `docs/service-rules/consistency.md` | 「`audit-consistency.sh` の検査層: (1)〜(6)」 | 実際の `scripts/audit-consistency.sh` は**(1)〜(12)**。(7)共通所有ロック突合／(8)基盤自身のゲート無効化検出／(9)要件一覧突合／(10)参照にできない複製の同期／(11)参照方式の退化検出／(12)所在の正本の実在検査 が記載から漏れている |
| `common/README.md` | 「`scripts/resolve-common.sh` … 共通リポのルートを解決する**唯一の起点**」 | 実行コードからは呼ばれていない（§7.1） |

### 7.5 実体はあるがドキュメントに書かれていないもの

- **`.claude/skills/` の3スキル**（`audit-ai-rules` / `extract-requirements` / `verify-request`）と **`.claude/agents/` の2エージェント** — ルート README のツリーには `.claude/` の1行しか無く、どのスキル・エージェントがあり何をするかを一覧した場所がリポジトリ内に存在しない。`audit-ai-rules` が配布対象外である旨は `scripts/audit-consistency.sh` の `FOUNDATION_ONLY` 配列のコメントにのみ書かれている
- **`.claude/settings.json` の `hooks` セクションが root と `profiles/_base` で異なる** — root は `/home/node/.claude/scripts/...` の絶対パス、`_base` は `"$CLAUDE_PROJECT_DIR/.claude/scripts/..."`。`audit-consistency.sh` 検査(6)は `permissions` ブロックのみを正規化比較しており、**`hooks` は比較対象外**。この分岐が意図的かどうかを記した記述はどこにも無い（root の絶対パスは `.devcontainer/devcontainer.json` の `.claude` → `/home/node/.claude` マウントと整合しており、実運用上は動く）
- **`.claude/settings.json.bak`** — 作業ツリーに存在（git 未追跡・`.gitignore` の `.claude/*` で除外）。由来の記述なし
- **生成物と既存プロジェクトの CI 方式の乖離** — §4.3 のとおり、既存2プロジェクトは composite action 方式、今生成されるのは devcontainer + make 方式。この2方式が並存している事実と、どちらに寄せるのかを書いた文書は無い（`service-templates/README.md` の「将来 `_base` を撤去した時点で」が最も近い記述）

### 7.6 置換済み・失効として明示されているもの（`docs/decisions/README.md` に記載あり）

- ADR-003（逆輸入モデル）→ 009・010 に置換
- ADR-005（順輸入 pull 型）→ 010 で失効
- ADR-004 の CODEOWNERS 部分・ADR-007 の批准系 → 008 で廃止
- `audit-consistency.sh` の旧検査(6) CODEOWNERS、旧 `.backport-manifest` 検査は、コードから削除済み＋削除理由がコメントで残されている（「`[ -f ... ]` 付きのまま残すと無言でスキップされる検査になる」）

### 7.7 意図的な複製（死んでいないが二重管理）

| 対 | 強制方法 |
|---|---|
| `common/scripts/check-*.sh` ↔ `.github/actions/*/check-*.sh`（3対） | 検査(10) `MIGRATION_PAIRS` が diff 一致を強制。実測でバイト一致 |
| `common/docker/Dockerfile.base` ↔ `profiles/_base/.devcontainer/Dockerfile` | 同上 |
| root `.claude/{scripts,skills,agents}` ↔ `profiles/_base/.claude/...` | 検査(6)が diff 一致を強制。`settings.json` は permissions のみ比較 |
| `service-templates/*` ↔ `profiles/_base/*` | 検査(10)後半が diff 一致を強制（`NEW_FORM_RE` の4件を除く） |
| プロファイル `settings.json` ↔ `_base` の `settings.json` | 検査(6)が `.permissions.ask` を除いた一致を強制 |
| マーカー上方探索ロジック | 5箇所にインライン重複。突合する検査は**無い** |

---

## 8. プロジェクト固有情報の混入

grep 条件: `sumai[-_ ]?desk|grace[-_ ]?tech|gracetech`（大文字小文字無視）、ドメイン名パターン、`tenant|rls|物件|入居者|賃貸|管理会社`。除外: `.git/`・`projects/`・`node_modules/`・Claude Code のランタイム `.claude/` 配下（`scripts`/`skills`/`agents` は別途個別に確認）。

**ヒット総数 23件。うち配布物に載るものは 2件。**

### 8.1 配布物に混入しているもの（生成プロジェクトに実際にコピーされる）

| ファイル | 行 | 内容 | 配布経路 |
|---|---|---|---|
| `profiles/_base/.claude/scripts/guard-dangerous.sh` | 209 | `旧経緯: rm は 2026-07-25 に追加された（sumai-desk の申し送り。…` | `new-service.sh` が全プロジェクトへコピー |
| `.claude/scripts/guard-dangerous.sh` | 209 | 同一（root 側の複製。検査(6)で `_base` と同期強制） | 基盤リポ自身 |

コード実体ではなくコメント中の出典表記。2026-07-24 の棚卸し（`docs/audit/inventory-20260724.md`）では、同種の混入（`extract-requirements/SKILL.md:31` の「sumai-desk からの逆輸入知見」）が「不変条件違反・修正S/優先度高」と判定され、その後修正されている（現在の SKILL.md には該当記述なし）。この `guard-dangerous.sh:209` は同じ類型だが未対応で残っている。

### 8.2 配布されないが基盤側に残っているもの

| ファイル | 件数 | 内容 |
|---|---|---|
| `common/scripts/check-tier-tripwire.sh:63` | 1 | 「2026-07-25 sumai-desk から基盤へ取り込み」（コメント） |
| `.github/actions/tier-tripwire/check-tier-tripwire.sh:63` | 1 | 同一（複製のため） |
| `service-templates/claude/scripts/guard-dangerous.sh:209` | 1 | §8.1 と同一のコメント |
| `service-templates/.github/workflows/ci.yml` | 3 | `uses: gracetech-jp/ai-dev-foundation/.github/actions/...@v1` — **組織名がハードコード**。ただし composite action の参照には org 名が必須で、代替表現が無い |
| `docs/decisions/006-adr-profile-based-bootstrap.md` | 6 | 「SumAI Desk 系」「グレイステックHP」「gracetech-jp ソロ運用」「`new-service.sh grace-tech-hp --profile product-static`」 |
| `docs/decisions/007-requirements-traceability.md` | 1 | 「sumai-desk 等 既存サービスへの展開」 |
| `docs/decisions/010-reference-only-common-assets.md` | 1 | 「（sumai-desk・2026-07-30）」 |
| `docs/audit/inventory-20260724.md` | 7 | 前回棚卸しの記録（固有名の混入検査結果そのもの） |

`docs/decisions/` と `docs/audit/` については、前回棚卸しで「ADR＝意思決定の**記録**であり配布されない（`new-service.sh` は `_base/docs/decisions` のみ配布）」として**問題なし**と判定されている。実際に生成物へコピーされるのは `profiles/_base/docs/decisions/{README.md,000-template.md}` の2ファイルのみで、固有名を含む ADR 本体は入らない。

### 8.3 ドメイン語・テーブル名・ドメイン名

- **ドメイン名**: 実在ドメインの混入はなし。ヒットしたのは `ghcr.io`（gitleaks イメージ）、`input.com`（guard-dangerous.sh のコメント中の例示文字列）、`env.dev`（settings.json の `.env.development` パターンの部分一致）のみ
- **テーブル名・業務ドメイン語**: `tenant` / `RLS` / `課金` / `billing` / `Stripe` / `名寄せ` / `物件` などのヒットは、すべて **「これらを書いてはいけない」という禁止語の定義側**（`docs/decisions/006` §3.1 のドメイン境界、`tests/tier-tripwire.bats:4` の「固有ドメイン語は使わない」宣言コメント、前回棚卸しの検索条件）。実際にドメイン概念として使われている箇所はゼロ
- **`profiles/product-web/files/app/main.py`** は `/health` エンドポイントのみで、業務エンドポイント・認証・モデル定義・テーブル・マイグレーションを意図的に含まない旨が docstring に明記されている
- **`compose.yaml`** の PostgreSQL も初期化SQL・スキーマを配らず、DB を空で起動する

---

## 付録: 実行して確認した事実の一覧

| 確認内容 | 結果 |
|---|---|
| `./scripts/new-service.sh demo-product-web --profile product-web` | exit 0、31ファイル生成 |
| `./scripts/new-service.sh demo-product-static --profile product-static` | exit 0、29ファイル生成 |
| `make audit-all` | 12層すべて通過（緑） |
| `make req-coverage` | 緑（ベースライン0件） |
| `make tier-tripwire` | 緑（差分基準 origin/main・機微変更なし） |
| `make lint` | 緑（shellcheck 警告なし） |
| `make test` | 緑（bats 235/235） |
| `diff common/scripts/check-*.sh .github/actions/*/check-*.sh` | 3対とも完全一致 |
| `diff .claude/scripts/*.sh profiles/_base/.claude/scripts/*.sh` | 一致（settings.json のみ差分＝ロック deny 14件） |
| `git ls-files .vscode` | 0件（空ディレクトリ） |
| `grep -rn "resolve-common"` | 実行コードからの参照0件 |
| `projects/*/. github/workflows/ci.yml` の `uses:` | 2プロジェクトとも composite action を使用 |

**未確認事項**
- GitHub 上のブランチ保護設定・必須ステータスチェックの有無（リポジトリ設定はローカルからは読めない。`gh` CLI もこの環境には無い）
- CI の直近実行結果（同上）
- `gracetech-jp/ai-dev-foundation` の `v1` タグが composite action の現在の実体と一致しているか（リモート未取得）
- Claude Code のツール層で `Edit(...)` deny が実際に拒否されるかの実測（前回棚卸しでも「設定の実在のみ確認」に留まっている）
