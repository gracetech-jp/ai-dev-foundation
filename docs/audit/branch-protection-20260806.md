# ブランチ保護の設定内容（確定案）— 2026-08-06

ADR-011「未解決」（CI が赤でもマージを機械的に止める配線が無い）への回答。
public 化でブランチ保護が無料で使えるようになったので、**何をどう設定するか**をここに置く。

**設定作業はこの環境からは行えない**（コンテナへ渡している PAT に `Administration` を渡していない。
`gh api .../branches/main/protection` は 403。これは意図した上限で、`verify-isolation.sh` 5/6 (d) が
「Administration が無いこと」を実測している）。**画面での設定は人が行う。**

> **改版（2026-08-06・第2版）**: 初版の「基盤は force push 禁止だけ先に入れる（案 B）」を**撤回**する。
> 必須ステータスチェックを伴わない保護は PR という形を強制するだけで、**テストが通ることを何も
> 保証しない**——この基盤が繰り返し潰してきた「作動していないゲート」そのものになる。
> 直 push を諦める代わりに **auto-merge** を使う（§5）。

---

## 1. 【A】ジョブ名の衝突 — 基盤・雛形ともに衝突なし

チェック名は「ジョブ名」で、reusable workflow 経由では
**`<呼び出し側のジョブ id> / <reusable 側のジョブ名>`** になる（プレフィックスが付く＝別の文字列になる）。
**同一リポジトリ内で同じチェック名が2つ以上のワークフローから報告されると、必須チェックの
判定先が曖昧になり PR が永久に止まる**（GitHub の警告）ため、全ファイルを走査した。

| ファイル | トリガ | ジョブ id | 実際に出るチェック名 |
|---|---|---|---|
| `.github/workflows/ci.yml` | push / pull_request | `audit` `lint` `test` `req-coverage` `tier-tripwire` `secret-scan` | 同左（素のジョブ名） |
| `.github/workflows/service-ci.yml` | **workflow_call のみ** | `gates` `gates-db` `secret-scan` | 呼ばれた側なので**必ず接頭辞が付く** |
| `.github/workflows/service-ci-selftest.yml` | **workflow_dispatch のみ** | `selftest` | `selftest / gates` `selftest / gates-db` `selftest / secret-scan` |
| `profiles/_base/.github/workflows/ci.yml`（配布雛形） | push / pull_request | `gates` `audit` `secret-scan` | 同左 |
| `service-templates/.github/workflows/ci.yml`（廃止予定） | push / pull_request | `stack-gates` `req-coverage` `tier-tripwire` `coverage-floor` `audit` `secret-scan` | 同左 |

**衝突は無い。** `secret-scan` は `ci.yml` と `service-ci.yml` の両方にあるが、後者は
`workflow_call` 専用で単独では走らず、呼ばれると `selftest / secret-scan` のように接頭辞が付く。
`gates` が `service-ci.yml` と `profiles/_base` の両方にあるのも同じ理由で衝突しない
（別リポジトリの話でもある）。**改名は不要。**

**ただし1件、実装を変えた**: selftest の呼び出し側ジョブ id を `ci` → **`selftest`** に改名した。
理由は2つ。

1. サービス側の雛形は呼び出し側を `ci` にする（ADR-011）。selftest も `ci` だと、
   接頭辞が「呼び出し側のジョブ id」なのか「`ci` という定数」なのかを実測で区別できない。
   `selftest / gates` が出れば前者だと確定する。
2. **基盤の必須チェックにこの名前を入れてはならない**ことが名前から分かる（§2）。

### 1-1. 既存2プロジェクト（保護をかける対象なので併せて確認）

| リポジトリ | ワークフロー | ジョブ名 | 衝突 |
|---|---|---|---|
| `grace-tech-hp` | `ci.yml`（push / PR）のみ | `stack-gates` `req-coverage` `tier-tripwire` `audit` `secret-scan` `display-green` | 無し（ワークフローが1本） |
| `sumai-desk` | `ci.yml`（push / PR） | `req-coverage` `tier-tripwire` `secret-scan` `migration-import-guard` | 無し |
| 〃 | `deploy.yml`（**push: main / workflow_dispatch**） | `test-backend` `test-frontend` `typecheck-frontend` `lint-backend` `audit-dependencies` `consistency` `migration-check` `build` `deploy-production` | 無し（`ci.yml` と重ならない） |

---

## 2. 【B】pull_request で走るか — **1件、実害のある欠落を発見**

必須チェックは **PR の head に対して走ったときだけ**マージ判定に現れる。
push でしか走らないワークフローのジョブを必須にすると、**PR は永久にブロックされる**。

| リポジトリ | 必須候補 | pull_request で走るか |
|---|---|---|
| `ai-dev-foundation` | `ci.yml` の6ジョブ | ✅ 走る（`on: push, pull_request`） |
| 〃 | `selftest / *` | ❌ **走らない**（workflow_dispatch 限定）。**必須にしないこと** |
| `grace-tech-hp` | `ci.yml` の5ジョブ（`display-green` を除く） | ✅ 走る |
| `sumai-desk` | `ci.yml` の4ジョブ | ✅ 走る |
| 〃 | `deploy.yml` の9ジョブ | ❌ **走らない**（`push: branches: [main]` と手動のみ） |

### 2-1. 発見: `sumai-desk` は**テストが PR で走っていない**

`deploy.yml` の `test-backend` / `test-frontend` / `typecheck-frontend` / `lint-backend` /
`migration-check` は **main への push でしか走らない**。つまり、

- PR の時点で走るのは `ci.yml` の4ジョブ（`req-coverage` / `tier-tripwire` / `secret-scan` /
  `migration-import-guard`）**だけ**。**テストは1つも走らない。**
- テストが走るのは**マージした後**（main への push）。落ちても、そのとき main は既に赤い。

**この状態で PR 必須のブランチ保護を入れると、「PR は緑だがテストは未実行」がそのまま
「機械が保証した緑」に見えるようになる。**保護は入れてよいが、**入れただけでテストが守られたと
読まないこと。** 対処は次のいずれかで、これはブランチ保護の設定とは別作業になる。

1. `deploy.yml` のテスト系ジョブに `pull_request` トリガを足す（最小の手当て）
2. ADR-016（リリースフェーズ）でテスト系を `ci.yml`／reusable 側へ移し、`deploy.yml` は
   デプロイだけを持つ形にする（設計としてはこちらが正しい）

**したがって sumai-desk は今回の保護対象から外す**（保留の判断と理由: §5-1）。

---

## 3. 【C】衝突検査の機械化 — **実装済み（検査(16)）**

判断: **実装する価値はある。ただし検査の中心は「ジョブ名の一意性」ではない。**

検査(15) のコメントにある方針（*ゲートは踏んだ穴から育てる。仕様の可用性表を丸ごと実装しない*）
に照らすと、今回の走査結果は次のように分かれる。

| 候補 | 実際に踏んだか | 失敗したときの壊れ方 | 判断 |
|---|---|---|---|
| ジョブ名の一意性 | **踏んでいない**（5ファイル走査して衝突ゼロ） | PR が止まる＝**fail-closed**。気付ける | 優先度は低い。**ついでに実装するなら可** |
| 必須候補が `pull_request` で走るか | **踏んだ**（`sumai-desk` の `deploy.yml`） | PR が緑のまま**テストが走らない**＝**fail-open**。気付けない | **実装すべき** |

この基盤が最も嫌う類型は後者（「作動していないゲート」）である。前者は止まるので誰かが必ず気付く。

### 3-1. 実装した形（2026-08-06）

問題は、**必須チェックの設定がリポジトリの外（GitHub の設定）にあり、`make audit-all` から
見えない**ことにある。そこで**リポジトリ内に宣言を持たせて、宣言を検査する**形にする。

```
.github/required-checks.txt   # 必須チェックに指定する“べき”名前を1行1つ（コメント可）
```

検査(16) が見るのは次の3点。**外の設定は見に行かない**（トークン権限にも依存しない）。

1. 宣言された名前が、実在するワークフローのジョブとして定義されていること
2. そのジョブを持つワークフローが **`pull_request` でトリガされる**こと（← §2-1 を機械で防ぐ）
3. `.github/workflows/*.yml` 全体でジョブ名が重複しないこと（`workflow_call` 専用ファイルは
   接頭辞が付くので除外する）

宣言と実設定の突き合わせは、Administration 権限のある環境で
`gh api .../branches/main/protection --jq '...contexts'` と diff すれば1コマンドで済む。
**「設定が正しいこと」は機械化できないが、「設定できる形になっていること」は機械化できる。**
できない部分を無理に取り込まないのは検査(15) と同じ線引きである。

**実体**（ADR-010 に従い共通側に1本だけ置き、配布雛形からも同じものを呼ぶ）:

| ファイル | 役割 |
|---|---|
| `common/scripts/check-required-checks.sh` | 検査の実装（①②③）。GitHub API は叩かない |
| `scripts/audit-consistency.sh` 検査(16) | 基盤側の呼び出し |
| `profiles/_base/scripts/audit-consistency.sh` 検査(6) | 配布雛形側の呼び出し（マーカー上方探索で共通側を解決） |
| `.github/required-checks.txt` / `profiles/_base/.github/required-checks.txt` | 宣言（基盤用・配布初期値） |
| `tests/check-required-checks.bats`（18ケース） | 検査そのものの回帰。全ケースが「正常な構成を1箇所だけ壊す」変異注入 |
| `tests/audit-consistency.bats` / `tests/new-service.bats` に各2〜3ケース | **監査から実際に呼ばれているか**（配線）。呼び出しが外れても単体テストは緑のままなので別に見る |

**限界（承知のうえで単純にしている）**: matrix ジョブの `job (値)` 形は未対応。
`ci / gates` のような呼び出し先の名前は別リポジトリにあるため接頭辞しか検証できない。
YAML パーサではなく行の形（2スペースのジョブ id・4スペースの `name:`）で見る。

---

## 4. 【strict】マージ前にブランチを最新にする — **OFF。ただし根拠は「根拠が無い」**

**GitHub のドキュメントに、strict を入れるべき条件の指針は無い。** 機能の説明があるだけで、
どういうリポジトリで有効かは書かれていない。**したがって一般論としての根拠は無い。**

その上で、このリポジトリ固有の材料は次の2つ。

- **閉じている窓**: `pull_request` イベントはマージ結果（`refs/pull/N/merge`）をチェックアウトして
  走るため、「PR 単体では緑だがマージすると壊れる」の大半はすでに検出できている。
- **残る窓**: `tier-tripwire` は `origin/main` との差分で判定する。PR 作成後に base が動き、
  かつ再実行されなかった場合、base 側で入った機微変更を見落としうる。

残る窓を閉じたいなら、正しい道具は strict ではなく **merge queue**（マージ直前に最新 base で
1回だけ走らせる）である。strict は base が動くたびに全 PR を更新→再実行させるため、
実質的にマージが直列化し、**auto-merge（§5）とも相性が悪い**——
auto-merge は base の取り込みを自動ではやらないので、`strict` + `auto-merge` は
「最新でないので待ち続ける」状態を作りうる。

**結論: OFF。** 理由は「入れるべき根拠が無く、auto-merge 運用と噛み合わないため」。
**実害（stale な PR がすり抜けた事例）を1件でも観測したら、strict ではなく merge queue を検討する。**

---

## 5. 【auto-merge】直 push を諦められる理由

必須チェックを有効にすると `main` への直 push はできなくなる（push しようとするコミットには
まだチェック結果が無いため）。ここが基盤リポの現行運用（CLAUDE.md「MVP フェーズ中は
main 直 push を例外的に許可」）とぶつかっていた。

**auto-merge を有効にすれば、待つ必要は無くなる。** PR を作って auto-merge を予約すれば、
必要なチェックが緑になった時点で GitHub が自動でマージする。人が緑を待つ工程は消える。

```
git switch -c feature/xxx && git push -u origin feature/xxx
gh pr create --fill
gh pr merge --auto --squash     # 緑になり次第マージされる
```

- 手数は「直 push 1回」→「push + 2コマンド」。**待ち時間は増えない。**
- コンテナ内から実行できる（PAT に Contents: Read and write がある。2026-08-06 拡大）。
  ただし **`git push` は Claude が実行しない**（CLAUDE.md）ため、実行者は人間のまま。
- `--squash` は「Require linear history」と整合する。

**したがって基盤リポも他2つと同じ設定でよい。**フェーズによる例外を作らない。
CLAUDE.md の「MVP 開発フェーズ中は main 直 push を例外的に許可」は、この設定を入れた時点で
実態と食い違うので、**設定後に `docs/rules/git.md` と CLAUDE.md の該当行を更新すること**
（この作業は保護を入れてから行う。順序を逆にすると、ルールだけ変わって機械が追いつかない）。

---

## 5-1. `sumai-desk` は今回の対象から外す（保留・2026-08-06 決定）

**理由: PR でテストが走らない状態で保護を入れると、「PR は緑だがテストは未実行」が
“機械が保証した緑”に見えるようになるから。**保護を入れること自体が、この基盤が繰り返し
潰してきた「作動していないゲート」を1つ増やす行為になる。**入れないほうがマシ**という判断である。

- §2-1 のとおり、テスト系（`test-backend` / `test-frontend` / `typecheck-frontend` /
  `lint-backend` / `migration-check`）は `deploy.yml` にあり、`push: branches: [main]` でしか走らない
- PR 時点で走るのは `ci.yml` の4ジョブだけ。**必須チェックに指定できるものの中にテストが1つも無い**
- 保護を入れると PR 必須になり、**テストが走るのはマージ後**という現状が固定される。
  「PR が緑＝マージしてよい」という誤った読み方を、機械が裏書きしてしまう

**先に片付けること**（どちらか）:

1. `deploy.yml` のテスト系ジョブに `pull_request` トリガを足す（最小の手当て）
2. テスト系を `ci.yml`／reusable 側へ移し、`deploy.yml` はデプロイだけにする（設計としては正しい）

**扱う時期**: このプロジェクトは devcontainer の compose 化を別途進めており、
`Makefile` の docker 呼び出しが全面的に書き換わる。CI の構成変更を先行させると二重の変更が衝突する
（ADR-011 結果節「動的アプリ側は compose 化の完了を待つ」と同じ理由）。**compose 化と同じ回で扱う。**

保留の間、このリポジトリの `main` は保護されないままである。**それは承知のうえの状態**であり、
「保護したつもり」で放置される状態より観測しやすい。片付いたら §6-1 に contexts を追記する。

---

## 6. 【D】最終的な設定内容

**対象は `ai-dev-foundation` と `grace-tech-hp` の2本**（`sumai-desk` は §5-1 のとおり保留）。
2本とも同じ形にする。違うのは `contexts` だけ。

| 設定項目 | 値 | 備考 |
|---|---|---|
| Do not allow force pushes（`allow_force_pushes: false`） | **必須** | 画面では既定で無効だが、**API から作ると明示しない限り許可されうる**。必ず明示する。CLAUDE.md が禁じている `git push --force` を機械で裏打ちする |
| Do not allow deletions（`allow_deletions: false`） | **必須** | 同上（`git branch -D` 系の事故） |
| Require status checks to pass | **有効**（`contexts` は下表） | ADR-011 未解決の本体。**これが無い保護は形だけ** |
| ├ strict（最新であること） | **false** | §4 |
| Require a pull request before merging | **有効** | 必須チェックを入れた時点で直 push は不可なので、形を揃える |
| ├ Required approvals | **0** | 人間レビューを必須にしない（ADR-008・機械ゲートで質を担保）。PR という器だけ使う |
| ├ Dismiss stale approvals / Require code owner review | 無効 | 承認0運用では意味を持たない。CODEOWNERS は ADR-008 で廃止済み |
| Allow auto-merge（リポジトリ設定） | **有効** | §5。ブランチ保護ではなく**リポジトリ設定**側にある（Settings → General） |
| Require linear history | **有効** | squash / rebase 前提。`--squash` と揃う |
| Require conversation resolution | 無効 | 承認0運用では実質機能しない |
| Require signed commits | 無効 | 運用コストに見合わない。コンテナから push する構成と相性が悪い |
| Do not allow bypassing the above settings（`enforce_admins: true`） | **有効** | ここを外すと保護は「お願い」になる。緊急時は保護を一時的に外す（設定変更は監査ログに残る） |

### 6-1. `contexts`（必須チェック名）

| リポジトリ | contexts | 注意 |
|---|---|---|
| `ai-dev-foundation` | `audit` / `lint` / `test` / `req-coverage` / `tier-tripwire` / `secret-scan` | **`selftest / *` を入れない**（workflow_dispatch 限定＝ PR で報告されず永久ブロック） |
| `grace-tech-hp` | `stack-gates` / `req-coverage` / `tier-tripwire` / `audit` / `secret-scan` | `display-green` は**入れない**。§6-2 のとおり同時に廃止する |
| ~~`sumai-desk`~~ | **保留**（§5-1） | PR でテストが走らないため、保護を入れると空虚な緑を機械が裏書きする |

ADR-011 の reusable へ移行した後は、サービス側の contexts を
**`ci / gates`**（＋ `ci / secret-scan`）へ張り替える。`ci` は各プロジェクトの `ci.yml` が置く
ジョブ id。**この接頭辞の形は selftest の実行で確定させる**（未実行）。
`ci / gates-db` は `db: none` のとき skip されるため、**contexts に入れない**
（skip の扱いに依存しないほうが安全）。

### 6-2. `display-green` の廃止 — 廃止でよい

集約ジョブは「必須チェックが使えない環境で緑を1点に集約して目視する」ための道具だった。
必須チェックが使える今、その役目は保護設定が引き取る。加えて集約ジョブは **skip の伝播**
（`needs:` のジョブが skip されると集約側も skip になる）という穴を持ち込む。

**廃止する。ただし単独で消さず、必須チェックを実ジョブ名で設定するのと同じ回で消すこと。**
先に消すと保護が存在しないチェックを要求して PR が止まる（安全側だが作業は止まる）。

### 6-3. 適用順序

1. `grace-tech-hp` の `feature/reference-only-common-assets`（未 push・2コミット）を先に PR で入れる。
   保護を入れてからだと、最初の PR が「保護を入れた直後の作業」になって切り分けが難しい
2. **2リポジトリ**（基盤・HP）に §6 の設定を入れる（`contexts` は §6-1）
3. HP の `display-green` を削除するコミットを PR で入れる（§6-2）
4. CLAUDE.md / `docs/rules/git.md` の「main 直 push を例外的に許可」を実態に合わせて更新（§5）
5. `sumai-desk`: compose 化と同じ回で `deploy.yml` を PR でも走らせる（§5-1）→ その後に保護を入れる

---

## 7. 設定後の確認

保護設定は git の外にあり、**退化を `make audit-all` で検出できない**。設定したら内容をここに追記して、
このファイルを記録の正本にすること（§3-1 の宣言ファイルを実装したら、そちらが正本になる）。

```
# 設定内容（Administration 権限のある環境で）
gh api repos/gracetech-jp/<repo>/branches/main/protection \
  --jq '{checks: .required_status_checks.contexts, strict: .required_status_checks.strict,
         force: .allow_force_pushes.enabled, del: .allow_deletions.enabled,
         admins: .enforce_admins.enabled, linear: .required_linear_history.enabled}'

# 実際に出ているチェック名（宣言と一致しているか）
gh api repos/gracetech-jp/<repo>/commits/<sha>/check-runs --jq '.check_runs[].name'
```

**skip されたジョブの扱い**（ADR-011 §8 の8）は 2026-08-06 の selftest で実測した。
`if:` で skip された `gates-db` も **check run 自体は作られ、conclusion が `skipped` になる**
（`selftest / gates-db  skipped`）。「報告されずに永久ペンディング」にはならない。
ただし**必須チェックがこれを合格として扱うか**は保護を入れないと測れないため、
**contexts に入れない方針（§6-1）を採ってこの仕様に依存しない。**

**チェック名の接頭辞**（同 4）も同時に確定した。`selftest / gates` が出たので、接頭辞は
**呼び出し側のジョブ id**（定数 `ci` ではない）。サービス側が雛形どおり `ci:` で呼べば
`ci / gates` になる、という §6-1 の記述はこれで裏が取れた。
