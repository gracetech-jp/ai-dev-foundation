# 資産棚卸レポート — ai-dev-foundation（2026-07-24）

監査範囲: working tree（**ADR-008 批准レス化・ADR-009 一方通行化を含む未コミット変更 52 件を含む**現状）。
実装・修正は行っていない（レポートのみ）。根拠は `パス:行` で示す。行番号は本日時点の working tree 基準。

---

## 1. サマリ

- **資産件数**: 101（git 追跡 98 ＋ 未追跡の新規 3: ADR-008/009・R-002）。生成物・ロックファイル・依存ディレクトリは存在しない（bash のみのリポ）。
- **判定内訳**: 維持 87 / 修正 14 / 廃止 0（廃止候補は §6 の条件付き2件のみ。COMMAND.md・批准機構・逆輸入は本日までの ADR-008/009 で撤去済み）。
- **重大な指摘（3件）**:
  1. **不変条件違反: 配布スキルに固有サービス名が混入** — `.claude/skills/extract-requirements/SKILL.md:31`（と `_base` 複製）に「sumai-desk からの逆輸入知見」。配布実体への固有名焼き込み禁止（ADR-007 M1）に違反。本日の批准レス化作業で混入したもの（修正S・優先度高）。
  2. **ゲート機構そのものが要件トレーサビリティの適用外** — R-001/R-002 が統べるのは guard/settings のみ。req-coverage・tier-tripwire・audit・new-service の各スクリプトと bats 4 本は要件IDを持たず（孤立実装・孤立テスト）、「基盤の機構は要件化する/しない」の方針が未宣言（§5）。
  3. **意思決定記録のステータス運用が自身のルールに不追従** — 配布する ADR 運用ガイド（`profiles/_base/docs/decisions/README.md:9-10`）は「覆された決定に『置換済み（→NNN）』を付す」と定めるが、ADR-003/004/005/007 は ADR-008/009 に部分的に覆されたまま無印（§5）。

---

## 2. 資産インベントリ表

凡例 — 種別: 要件管理/ゲート/CI/テンプレート/ドキュメント/スクリプト/設定。利用主体: 人間/CA(コーディングエージェント)/CI。⚠=呼び出し元なし（参照孤立）。

### 2.1 ルート設定・規約（7件）

| パス | 種別 | 利用主体 | 参照元 | 判定 | 根拠 |
|---|---|---|---|---|---|
| CLAUDE.md | ドキュメント | CA | セッション自動ロード・配布(new-service.sh:99) | 維持 | ADR-008/009 反映済み |
| README.md | ドキュメント | 人間 | 入口 | **修正(S/低)** | :103 tests/ の説明が3種のみで new-service/audit-consistency bats に触れず |
| Makefile | ゲート | 人間/CA/CI | pre-push:8-49・ci.yml:21-53 | 維持 | ターゲット契約=quality-gates.md §1 |
| .gitignore | 設定 | git | — | 維持 | .backport-backup 行は本日撤去済み |
| .editorconfig | 設定 | エディタ | — | 維持 | code-style.md:1 の機械強制 |
| .backport-manifest | 設定 | スクリプト | sync-from-common.sh:76(COMMON側として) | 維持 | 名称は互換維持を :5 で自己文書化 |
| .req-coverage-baseline / .tier-tripwire-allow / docs/requirements/.tier-tripwire-none | ゲート | ゲートスクリプト | check-requirements-coverage.sh:113-125 / check-tier-tripwire.sh:21-22,44 | 維持 | 空/宣言ファイル。B3・機微面なし宣言の実体 |

（3行目は3ファイルを1行に集約。件数計上は個別）

### 2.2 .claude/（ガードレール。8件＋_base 複製7件）

| パス | 種別 | 利用主体 | 参照元 | 判定 | 根拠 |
|---|---|---|---|---|---|
| .claude/settings.json | 設定 | CA(Claude Code) | ハースが読込。hooks 定義 :58-80 | 維持 | R-001 paths。root にはロック deny を置かない設計=audit:190-206 |
| .claude/scripts/guard-dangerous.sh | ゲート | CA | settings.json:74(PreToolUse) | 維持 | R-001/R-002 の実体。基盤スキップ :114 |
| .claude/scripts/session-start-rules.sh | ゲート | CA | settings.json:61(SessionStart) | 維持 | G5。インデックス注入 :21-30 |
| .claude/skills/extract-requirements/SKILL.md | テンプレート | CA | ユーザー起動(/extract-requirements) | **修正(S/高)** | :31 に固有名「sumai-desk」（不変条件違反。§4） |
| .claude/skills/verify-request/SKILL.md | テンプレート | CA | ユーザー起動。基盤自身では実質未使用⚠ | 維持 | 配布鏡として必要（audit:180-186 が root↔_base 一致を強制） |
| .claude/skills/audit-ai-rules/SKILL.md | テンプレート | CA | ユーザー起動。基盤のみ(audit:161) | **修正(S/低)** | :37 に基盤に存在しないサービス由来パス例「backend/app/modules/」 |
| .claude/agents/consistency-auditor.md / security-reviewer.md | テンプレート | CA | Agent tool から起動 | 維持 | スタック中立を確認 |
| profiles/_base/.claude/*（settings・guard・session-start・skills2・agents2） | 配布複製 | 配布 | new-service.sh:88-95・audit:170-186(同期強制) | extract-requirements のみ**修正(S/高)**、他は維持 | root と diff 一致を監査が機械強制 |

### 2.3 scripts/（8件）

| パス | 種別 | 利用主体 | 参照元 | 判定 | 根拠 |
|---|---|---|---|---|---|
| new-service.sh | スクリプト | 人間 | 手動実行。bats(tests/new-service.bats) | 維持 | ADR-006 プロファイル合成 |
| audit-consistency.sh | ゲート | 人間/CA/CI | Makefile:54・pre-push:8-16・ci.yml:21 | 維持 | 検査(1)〜(6)。CODEOWNERS 検査は撤去済み :143 |
| check-requirements-coverage.sh | ゲート | 人間/CA/CI | Makefile:39-43・pre-push:30-38・ci.yml:39-43 | 維持 | G1/G2/G4/B3 の実体（§3） |
| check-tier-tripwire.sh | ゲート | 人間/CA/CI | Makefile:50-51・pre-push:41-49・ci.yml:47-53 | 維持 | F2/S4 の実体。基盤は正当スキップ |
| check-coverage.sh | ゲート | サービスCI | 基盤では未使用（Makefile:33-34 でスキップ宣言)⚠ | 維持 | 配布物(new-service.sh:116)。数値検証 fail-closed :23-30 |
| pre-push | ゲート | 人間/CA | make install-hooks(Makefile:62)・postCreate.sh:16 | 維持 | 4段ゲート :8-49 |
| commit-msg | ゲート | 人間/CA | make install-hooks(Makefile:63) | 維持 | Conventional Commits 強制 :17-27 |
| sync-from-common.sh | スクリプト | 人間 | 手動実行（サービス側）。マニフェスト:19(自己ホスティング) | 維持 | ADR-009 で一方通行の唯一の更新経路 |

### 2.4 docs/rules/（11件）

| パス | 判定 | 根拠 |
|---|---|---|
| backport.md | 維持 | 本日一方通行版へ全面改訂。封鎖対象/例外の正 :20-38 |
| code-style.md / security.md / testing.md / token-efficiency.md / git.md / consistency.md / quality-gates.md / tiers.md / requirements.md / repo-layout.md | 維持 | ADR-008/009 の記述反映を確認（廃止参照の残存スイープ0件。§5） |

（利用主体: CA(SessionStart インデックス経由)＋人間。参照元: session-start-rules.sh:24-29 が全 .md を自動列挙するため参照孤立なし）

### 2.5 docs/decisions/（9件）・docs/requirements/（4件）・docs/service-rules/（1件）

| パス | 判定 | 根拠 |
|---|---|---|
| ADR-001/002/006 | 維持 | 現行機構と一致 |
| ADR-003(逆輸入モデル) / 005(pull型順輸入) | **修正(S/中)** | ADR-009 が 003 を実質置換・005 の記述の一部（双方向前提）を更新。ステータス無印のまま（_base decisions README:9-10 の自ルール違反） |
| ADR-004(ガードレール配布) | **修正(S/中)** | CODEOWNERS 配布の記述が ADR-008 で廃止済み。置換注記なし |
| ADR-007(要件トレーサビリティ) | **修正(S/中)** | G3/F1/F3/B1 等が ADR-008 で廃止。冒頭に「一部 ADR-008 で廃止」の注記なし（quality-gates.md:9-10 には注記あり） |
| ADR-008 / ADR-009（未追跡） | 維持 | 本日作成。コミット待ち |
| R-001-guardrail-enforcement.md | 維持 | ratified・bats被覆(tests/guard-dangerous.bats:9-10)・paths=guard/settings |
| R-002-common-owned-lockdown.md（未追跡） | 維持 | ratified・bats被覆(同:11-12)・本日作成 |
| docs/requirements/README.md / .tier-tripwire-none | 維持 | 批准レス版へ更新済み / 宣言者記名あり |
| docs/service-rules/consistency.md | 維持 | 検査層(6)への追従・ADR-009 分岐の記載 :52-54 |

### 2.6 profiles/（_base 24件・product-static 5件・product-web 10件）

| パス | 判定 | 根拠 |
|---|---|---|
| _base/Makefile・ci.yml・audit-consistency.sh・PROJECT.md.template・gitignore.template・.editorconfig・.env.example・.coverage-floor・.req-coverage-baseline・.tier-tripwire-allow・devcontainer3点・docs/requirements3点・docs/service-rules・docs/decisions2点 | 維持 | new-service.sh:82-128 が配布。audit:72-98 が配布漏れ/退化を機械検出 |
| _base/README.md.template | **修正(S/中)** | :20-23「該当ファイルも手動で同期してください」— sync-from-common.sh と矛盾（CLAUDE.md は手動同期を否定）。順輸入コマンド案内に更新すべき |
| product-static: manifest＋files4点 | 維持 | display-green。manifest 検証は new-service.sh:151-208（fail-closed） |
| product-web: manifest＋files9点 | 維持 | full-red。ドメイン語ゼロを確認（main.py はドメイン境界注記 :1-5 付き参照実装） |

### 2.7 .github/・.devcontainer/・tests/（8件）

| パス | 判定 | 根拠 |
|---|---|---|
| .github/workflows/ci.yml | **修正(S/低)** | :37 コメント「妥当性欠落・批准後改変を検出」が ADR-008 で廃止済みの機能に言及（挙動は正しい） |
| .devcontainer/Dockerfile・devcontainer.json | 維持 | jq 依存は audit:126-141 が退化検出 |
| tests/guard-dangerous.bats | 維持 | R-001/R-002 のマーカー被覆 :9-12。R-002 追加 :115-175 |
| tests/req-coverage.bats・tier-tripwire.bats・new-service.bats・audit-consistency.bats | **修正(M/中)** | @req マーカーなし＝孤立テスト（§5。対応する要件IDが存在しない） |

---

## 3. 実効性検証結果（ゲート別）

記号定義の正: `docs/decisions/007-requirements-traceability.md`「導入した機構」表（廃止分は ADR-008。参照: quality-gates.md:9-10）。

| 機構 | 定義箇所 | 発火経路（実在確認） | 状態 |
|---|---|---|---|
| P-0 Tier定義 | tiers.md:14-31（4軸最大値） | R-001/R-002 の front-matter tier / tripwire needs_s(check-tier-tripwire.sh:88-94) | **作動・定義と運用一致**（ADR-008 で人間批准行を撤去済み。厳格度表:40-47 と実装(未カバー即赤=check-requirements-coverage.sh:147・B3=:120・G4=:149)が対応） |
| G1 永続要件・一意ID | requirements.md §1-2 | front-matter 検証: check-requirements-coverage.sh:60-89（id 形式・tier 値・ID重複で exit 2） | **作動**（bats: tests/req-coverage.bats:96-107） |
| G2 要件↔テスト紐づけ | requirements.md §4 / testing.md:30-48 | マーカー走査 :93-105 → 未カバー判定 :146-157。経路: Makefile:39-43 → pre-push:30-38 → ci.yml:39-43 | **作動** |
| G3 要件のLLM編集封鎖 | （廃止・ADR-008） | 発火経路なし | **意図的廃止**（deny・guard 該当節撤去済み。guard-dangerous.sh:109-110 に廃止注記） |
| G4 negative space→adversarial | requirements.md §5 | check-requirements-coverage.sh:148-150 | **作動**（bats :70-79 で赤を回帰） |
| G5 SessionStart surface | session-start-rules.sh:32-63 | settings.json:58-68（SessionStart hook） | **作動**（本セッション冒頭の注入で実証。要件封鎖文は批准レス版に更新済み :58-60） |
| F2 Tierトリップワイヤ | tiers.md:55-61 | check-tier-tripwire.sh:137-188。経路: Makefile:50-51 → pre-push:41-49 → ci.yml:47-53 | **作動（ただし基盤では正当スキップ**: 空設定＋.tier-tripwire-none。実効はサービス側。挙動は bats tests/tier-tripwire.bats で担保） |
| B3 S/Aベースライン禁止 | requirements.md §4 | check-requirements-coverage.sh:114-125 | **作動**（bats :44-49） |
| S4 空虚な緑の静的検出 | ADR-007 | check-tier-tripwire.sh:190-206（警告のみ・非ブロック） | **作動（警告どまり＝設計どおり）** |
| R-002 共通所有封鎖 | ADR-009 / backport.md:20-31 | guard-dangerous.sh:114-127＋配布 settings deny（_base:52-81）。監査が退化検出 audit:201-206 | **作動**（本日サービス2リポで `sed -i CLAUDE.md` 相当が deny になることを実地確認。基盤スキップも bats :165-169） |
| F1/F3/B1（ハッシュ再批准・妥当性批准） | （廃止・ADR-008） | 発火経路なし | **意図的廃止**（廃止回帰 bats: tests/req-coverage.bats:32-40） |

### CI ゲート（基盤リポ・6ジョブ独立）

| ジョブ | 定義 | スキップ条件 | 直近の実行結果・時間 |
|---|---|---|---|
| audit | ci.yml:17-21 | なし（on: push/PR 全発火 :9-11） | **未確認**（下記） |
| lint | ci.yml:23-27 | なし | 未確認 |
| test | ci.yml:29-35 | なし | 未確認 |
| req-coverage | ci.yml:39-43 | なし | 未確認 |
| tier-tripwire | ci.yml:47-53 | なし | 未確認 |
| secret-scan | ci.yml:56-61 | なし | 未確認 |

- 直近実行はこの環境に `gh` CLI が無く未確認。**確認方法**: `gh run list --workflow=CI --limit 5`、または GitHub → gracetech-jp/ai-dev-foundation → Actions。
- ローカル等価実行は本日全緑を確認済み: `make lint / test(bats 68本) / req-coverage / tier-tripwire / audit-all`（secret-scan は docker 不在で未実行）。
- 配布 CI（profiles/_base/ci.yml:20-88）は 3 ジョブ構成（gates 統合＋TODO=exit 3 soft 契約 :44-56。req-coverage/tier-tripwire は soft 化しない :67-68）。実発火はサービスリポ側でのみ確認可能（未確認）。

### 意図的失敗の検証手順（実行はしていない）

1. audit: 存在しない docs/rules/ ファイルへの参照行を CLAUDE.md に足す → `make audit-all` が検査(1)で exit 1（audit:20-31）。
2. req-coverage: `tests/` に `# @req: R-999` を置く → dangling で exit 1（check:129-139）。
3. tier-tripwire: `.tier-tripwire-none` を削除し空設定のまま実行 → exit 2（check:42-48）。
4. commit-msg: `git commit -m "update stuff"` → 形式違反で exit 1（commit-msg:17-27）。
5. R-002: サービスリポで `echo x > docs/rules/git.md` を Claude の Bash 経由実行 → deny（guard:114-127。bats :117-121 で回帰済み）。

---

## 4. 不変条件検査（ドメイン語・固有名の混入）

全文検索: `sumai|grace-?tech|tenant|テナント|rls|課金|billing|stripe|名寄せ|resend|turnstile|物件|顧客`（追跡98＋未追跡3）。

### 違反（配布実体への混入）

| パス:行 | 該当語 | 混入経緯の推定 | 判定 |
|---|---|---|---|
| .claude/skills/extract-requirements/SKILL.md:31 | sumai-desk | 2026-07-24 の批准レス化作業で、サービス由来の知見を出典付きで逆輸入した際に固有名ごと転記 | **違反**（配布skill。修正S: 出典名を削り一般化） |
| profiles/_base/.claude/skills/extract-requirements/SKILL.md:31 | sumai-desk | 同上（複製） | **違反**（同時修正） |
| .claude/skills/audit-ai-rules/SKILL.md:37 | backend/app/modules/ 等 | 旧サービス実装時代の確認対象例が残存 | **準違反**（固有名ではないがサービススタック前提の例示。基盤専用skillのため影響小） |

### 誤検知（許容される使用）

| パス:行 | 該当語 | 理由 |
|---|---|---|
| docs/decisions/006:39-58,189,233 / 007:87 | SumAI Desk・grace-tech-hp・gracetech-jp・RLS・tenant 等 | ADR＝意思決定の**記録**であり配布されない（new-service.sh:106 は _base/docs/decisions のみ配布）。006:51 はむしろ禁止語の定義列挙 |
| tests/tier-tripwire.bats:4 | RLS/tenant/課金 | 「固有ドメイン語は使わない」という宣言コメント自体 |
| profiles/product-web/* の PostgreSQL/FastAPI 等 | スタック語 | プロファイル層はスタック依存物を持ってよい（ADR-006 不変条件の再定義。ドメイン語は不検出） |

---

## 5. ドリフト一覧

### ドキュメント ↔ 実装の乖離

| # | 箇所 | 乖離内容 | 判定 |
|---|---|---|---|
| D1 | .github/workflows/ci.yml:37 | コメントが「妥当性欠落・批准後改変を検出」— 実装(check script)は ADR-008 で当該検出を廃止済み | 修正S/低 |
| D2 | profiles/_base/README.md.template:20-23 | 「手動で同期してください」— 実際は sync-from-common.sh が正規経路（CLAUDE.md・backport.md と矛盾） | 修正S/中 |
| D3 | README.md:103 | tests/ の説明が「guard-dangerous / req-coverage / tier-tripwire の bats」— 実際は new-service.bats・audit-consistency.bats を含む5ファイル | 修正S/低 |
| D4 | ADR-003/004/005/007 | ADR-008/009 に覆された記述にステータス注記なし（配布ガイド _base/docs/decisions/README.md:9-10 の「置換済み（→NNN）」運用に不追従） | 修正S/中 |

### 要件ID ↔ 実装 ↔ テスト ↔ CIゲートの突合

- **孤立要件（実装なし）**: なし（R-001→guard/settings 実装あり・R-002→guard/settings 実装あり）。
- **孤立実装（統べる要件なし）**: check-requirements-coverage.sh・check-tier-tripwire.sh・audit-consistency.sh・new-service.sh・check-coverage.sh・pre-push・commit-msg・sync-from-common.sh。ゲート機構それ自体は要件IDを持たない。基盤は `.tier-tripwire-none`（機微面なし宣言）のため機械強制はされず、**「機構は要件化対象か」の方針が未宣言**のまま。
- **孤立テスト（@req マーカーなし）**: tests/req-coverage.bats・tier-tripwire.bats・new-service.bats・audit-consistency.bats（マーカー保持は guard-dangerous.bats のみ: :9-12）。
- 対応案（実装はしない）: (a) R-003〜R-006 として機構要件を起こしマーカー付与する、または (b) 「基盤の機構はbats直接担保とし要件化しない」を requirements.md か ADR に1行宣言する。いずれか未決のままが現状のドリフト。

---

## 6. 廃止候補リスト

**即時廃止すべき資産はなし**（COMMAND.md・批准機構一式・逆輸入一式は ADR-008/009 で撤去済み。働いていない機構の残存は検出されなかった）。条件付き候補のみ:

| 候補 | 条件・依存関係の注意 |
|---|---|
| .claude/skills/verify-request/SKILL.md（root側） | 基盤自身では未使用（アプリなし）。ただし監査(audit:170-186)が root↔_base の diff 一致を強制するため**単独削除は監査赤になる**。廃止するなら audit の FOUNDATION_ONLY 方式の逆（配布専用リスト）を先に実装 → その後 root 側を削除、の順 |
| `.backport-manifest` の名称 | 機能は順輸入に必須で廃止不可。「backport」名のみ役割喪失。改名（例 .sync-manifest）は既存サービスの旧 sync-from-common.sh が旧名を参照するため、**全サービスの sync スクリプト更新を先に配布 → その後改名**の2段階が必要 |

---

## 7. 未確認事項と確認方法

| # | 未確認事項 | 確認方法 | 状況（2026-07-25 追記） |
|---|---|---|---|
| 1 | 基盤 CI 6ジョブの直近実行結果・実行時間 | `gh run list --workflow=CI --limit 5`（要 gh 導入）または GitHub Actions UI | **未確認のまま**。`gh` がこの環境に無く、Actions の結果を取得する手段がない。あわせて CI は 3ジョブ統合済み（dc4a900）なので「6ジョブ」の前提自体が古い |
| 2 | secret-scan（gitleaks）のローカル動作 | docker 導入環境で ci.yml:61 のコマンドを手動実行 | **未確認のまま**。`docker` も `gitleaks` バイナリもこの環境に無い |
| 3 | 配布 CI（_base ci.yml の gates 統合・soft 契約）の実発火 | サービスリポの Actions で TODO ターゲットが warning・実装済みが red になることを確認 | **未確認のまま**。push しないと発火しない（push は手動運用） |
| 4 | R-002 の deny（ツール層）がサービス側 Claude Code セッションで効くこと | サービスリポで新セッションを開き Edit で CLAUDE.md を編集→拒否されることを確認 | **設定の実在のみ確認**（grace-tech-hp・sumai-desk とも `Write/Edit(CLAUDE.md)` `Write/Edit(docs/rules/**)` の deny が4件ずつ存在）。実際に拒否されるかはツール層の挙動なので、サービスで新セッションを開いての実測が必要 |
| 5 | devcontainers/ci@v0.3 のビルド成功（プロファイル生成物） | 生成サービスを push して gates ジョブのビルドログを確認 | **未確認のまま**（項目3と同じくpush待ち） |

> 1・2・3・5 は「この実行環境に道具が無い / push していない」ことが理由で、調べた結果わからなかった
> のではない。`gh`・`docker` を入れるか、push 後に GitHub 側で確認すれば片付く。

---

*監査実施: Claude Code（レポートのみ・実装なし）。ローカルゲートは lint / test(bats 68) / req-coverage / tier-tripwire / audit-all を全緑で確認。*

---

## 8. その後の是正（2026-07-25 追記）

本レポートは 2026-07-24 時点のスナップショットであり、以下の記述はその後の是正で状態が変わっている。
レポート本文は当時の記録として残し、差分だけをここに示す。

| 本文の該当箇所 | 当時の状態 | 現在 |
|---|---|---|
| §F2 Tierトリップワイヤ「基盤では正当スキップ」 | 空設定＋`.tier-tripwire-none` で F2・S4 とも一度も走っていなかった | **実発動する**。機微パスを R-001・R-002 の paths の和集合として定義し、宣言ファイルを撤去した |
| §孤立実装「基盤は機微面なしのため機械強制されない」 | 同上 | ガードレール骨格（`guard-dangerous.sh`・`settings.json`・`profiles/*/files/.claude/settings.json`）が R-001/R-002 に統べられた状態で機械強制される |
| §docs/requirements/README.md「宣言者記名あり」 | 人間批准前提の記述・R-001 の status を draft と誤記 | 批准レス版へ更新。README の表と要件ファイルの突合を監査層(9)で機械強制 |

あわせて、本レポートが指摘していなかった穴も同日に塞いだ:

- 共通所有ファイルの**削除**（`rm`）が deny も guard もすり抜けていた（破壊的コマンド検査は再帰＋強制の
  組み合わせしか見ないため）。sumai-desk の申し送り由来。
- 共通所有ロックの退化検出が「deny が1件でもあれば緑」で、大半が消えても素通りしていた。
- 共通所有ファイルの定義が guard の正規表現・配布 `settings.json` の deny・`.backport-manifest` に
  分散ハードコードされ、突合されていなかった（監査層(7)を追加）。
- 骨格の手動同期（`cp`）がロック自身に塞がれ、マニフェスト対象外ファイルの正規更新経路が消えていた。

監査層は (1)〜(6) から **(1)〜(9)** へ、bats は 68本 → **88本** に増えている。
