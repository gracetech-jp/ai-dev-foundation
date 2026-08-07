# 品質ゲート（共通テンプレ）

品質は「AIやレビュアーの善意」ではなく**機械的なゲート**で担保する。
ゲートは push 前（ローカル）と CI（リモート）で**二重化**し、片方が素通りしても他方で止める。

> 具体的なコマンド・ツール（テストランナー・lint・型検査・カバレッジ計測）はスタック依存のため
> 各サービスが `Makefile` ターゲットと `PROJECT.md` で定義する。ここには**原則と構造**だけを置く。
>
> ゲート記号（P-0・G1〜G5・M1〜M3・F1〜F3・B1〜B3・S1〜S4）の定義の正は、基盤リポ `ai-dev-foundation` の
> `docs/decisions/007-requirements-traceability.md`「導入した機構」表（一部の機構は ADR-008 の批准レス化で廃止。廃止一覧は同 ADR 参照）。本書は §番号で原則のみを記し、記号定義は複製しない。

---

## 1. Makefile ターゲット契約
各サービスは、スタックが何であれ以下の名前のターゲットを用意する（中身は自由）。
フック・CI・人間が同じ入口を共有できるようにするための規約。

| ターゲット | 役割 |
|---|---|
| `make test` | 全テスト実行 |
| `make lint` | 静的解析（**警告ゼロで失敗する設定**にする。下記3参照） |
| `make coverage` | カバレッジのフロア検証（一方向ラチェット。下記5参照。`common/scripts/check-coverage.sh` で判定） |
| `make req-coverage` | 要件↔テストのトレーサビリティ検証（`common/scripts/check-requirements-coverage.sh` で判定。詳細: `docs/rules/requirements.md`） |
| `make tier-tripwire` | Tier申告のコード実態からの裏取り（`common/scripts/check-tier-tripwire.sh` で判定。詳細: `docs/rules/tiers.md`） |
| `make audit-all` | 整合性監査一式（詳細: `docs/rules/consistency.md`） |
| `make audit-deps` | 依存パッケージの脆弱性監査（詳細: `docs/rules/security.md`） |
| `make install-hooks` | git フック（pre-push・commit-msg 等）をローカルに導入 |

## 2. push前ゲート（pre-push フック）
- **フックは CI の高速な部分集合である。** CI が権威あるゲートで、フックは速いフィードバックを返す
  ためだけにある。**フックに無いものが CI にあると「push して数分後に単純な問題で落ちる」**——
  2026-08-07 に実際に踏んだ（shellcheck の info 1件で CI が赤、ローカルは緑）。
  配置の基準は**速度**で、秒で終わるものはフック、分単位かかるものは CI に置く。
  両方で走る重複は正常であって無駄ではない（権威はあくまで CI 側）。
- 最初に **`make lint`** を実行する（shellcheck 系は秒で終わるので最速の指摘を先に返す）。
  判定は `run-gates.sh` の `optional` モード——**lint が未実装（TODO=exit 3）でも、ターゲットが
  無くても push は止めない**。共通フックは全リポジトリ共有であり、契約違反を赤にするのは
  CI（`softable`）の役目である。これはベストプラクティスではなく未実装スタックへの実装上の工夫。
- 続いて **`make audit-all` → `make test` → `make req-coverage` → `make tier-tripwire`** を順に実行し、
  失敗したら push をブロックする（`make all` と同じ4段。req-coverage / tier-tripwire がCIのみで強制されると
  要件未達の検出が push 後まで遅れるため、2026-07-22 にローカル側も4段へ揃えた）。
  機微面を持たないリポジトリは、機微パターンを空にしたうえで `docs/requirements/.tier-tripwire-none` を
  コミットすることで4段目を正当スキップする（fail-closed。宣言の書き方は `PROJECT.md` の Tier トリップワイヤ節）。
- 回避手段（`git push --no-verify`）の存在はメッセージに明示する（緊急避難用。常用しない）。
- フックは `make install-hooks` で導入。導入忘れに備え、CI側を最終防波堤にする（下記4）。
- **フックのリンクは必ず相対（`ln -sfr`）で張る。** devcontainer 内で絶対リンクを張るとホストからは
  解決できず、**git は解決できないシンボリックリンクを「フックが無い」と同じに扱って警告なしで素通りする**
  （2026-08-07、sumai-desk と基盤リポの両方でこの状態を発見）。落ちるより質が悪い——ゲートが在ると
  思ったまま1回も走らない。相対なら projects/ 配下にある限り（ADR-010）どちらの環境でも解決する。
  張られた結果は `common/scripts/check-git-hooks.sh` が監査で機械検査する。**検査の主眼は
  「相対であること」**で、存在・解決・実行権限だけを見ると監査環境では常に緑になり何も捕まらない。

## 3. lint はゼロ警告ゲート
- 「警告」を放置可能にしない。警告数の上限を **0** に設定し、警告が出たら失敗させる
  （例：多くのlinterが持つ「max-warnings=0」相当の設定）。
- 「後で直す」を許すと警告が累積し、本当に危険な指摘が埋もれる。閾値ゼロで常にクリーンに保つ。

## 4. CI 3ジョブ構成（gates 統合＋audit＋secret-scan）
- 配布 CI は3ジョブ：**`gates`**（lint / test / coverage / audit-deps / req-coverage / tier-tripwire を
  devcontainer ビルド1回で明示列挙実行）／**`audit`**（整合性監査・素runner）／**`secret-scan`**（gitleaks・素runner）。
  旧「ターゲットごとに独立ジョブ」構成はビルドが毎push×6回走るため 2026-07-23 に統合した（solo・MVP のコスト簡素化）。
- `gates` は `make all` を使わない（`all` は lint / coverage / audit-deps を含まない union 未満のため。
  明示列挙で「黙って落ちるターゲット」を作らない）。
- **fail/soft の原則：「未実装(TODO) = soft signal、規約違反 = red」**。赤は本物の違反にのみ予約する。
  - **TODO 契約**：Makefile 雛形の未実装ターゲットは **exit 3** を返す。CI は make の決定論的エラー行
    「`make: *** [...] Error 3`」で TODO を構造的に識別し soft（警告のみ・ジョブ継続）にする。
    実装したら exit 3 行を削除する＝以後の失敗は red。
  - **req-coverage / tier-tripwire は soft 化しない**（設定エラー exit 2 含め無条件 red。fail-closed 維持）。
  - **coverage は floor=0 の間は soft**。`make coverage` を実装し `.coverage-floor` を 0 より上げた時点で
    自動的に red 化する（発火に人手の切替操作は不要）。
- **build / deploy は全ジョブの成功を前提**にする（依存関係に含める）。1つでも赤ならデプロイに進めない。
- ローカルフックはあくまで早期検出用。**CIを唯一の必須ゲート**とみなす（フック未導入・`--no-verify`を吸収）。
- **CI が赤でもマージできる状態を残さない。** どのジョブをブランチ保護の必須チェックにするかは
  `.github/required-checks.txt` に宣言する。実設定は GitHub 側にあってリポジトリからは見えないため、
  監査は宣言だけを見る——①宣言した名前のジョブが実在する ②そのワークフローが **`pull_request` で走る**
  ③ワークフロー間でジョブ名が重複しない。とくに②が要る理由は、**必須チェックは PR の head に対して
  走ったときだけマージ判定に現れる**から。push でしか走らないジョブを必須にすると PR が永久に止まり、
  逆に「PR では走らないゲート」を必須のつもりで並べると**緑に見えて何も守らない**。
- **共通の reusable workflow を呼ぶときは `uses: ...@X` と `foundation-ref: X` を同じ値で書く。**
  省くと共通基盤の checkout が既定ブランチへ落ち、**タグでピン止めしても main のゲートで回る**
  （`github.job_workflow_sha` は空になる。2026-08-06 実測）。ずれても赤くならない——
  違うのは「どの版のゲートで検査したか」だけで症状が出ないため、一致は監査が機械強制する。

## 5. カバレッジのラチェット（一方向ラチェット）
- テストカバレッジに**数値下限**を設け、下回ったらCIを失敗させる。
- 下限は**上げることはあっても下げない**（ラチェット）。テストを増やしたら床も引き上げ、後退を防ぐ。
- 数値目標は `docs/rules/testing.md` を正とする（重複記載せず参照のみ。数値変更時の同期漏れを防ぐ）。
- 一気に高い値を課さず、現状値に合わせて設定 → 改善のたびに刻んで上げる運用にする。

---

## まとめ（原則）
- **プロンプト任せにしない**：「〜すべき」はフック/CIで機械的に強制できる形にする。
- **二重化**：push前とCIの両方。ローカルは速さ、CIは確実性。
- **後退防止**：カバレッジ床とゼロ警告で、品質が下がる方向の変更を機械的に弾く。
