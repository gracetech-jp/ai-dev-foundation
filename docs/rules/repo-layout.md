# リポジトリ構成の必須要素（共通）

全サービスリポジトリが備えるべきファイル/ディレクトリを定義する。これらは `scripts/new-service.sh` が
生成時に配布し、欠落は `scripts/audit-consistency.sh` の「配布漏れ検査」等で検出する。
人手のレビューに頼らず、**構成の欠落を機械的に検出**するのが目的。

## 必須ファイル / ディレクトリ

| パス | 役割 | 由来 |
|---|---|---|
| `CLAUDE.md` | AI駆動開発の共通ルール（基盤から配布・サービス側編集禁止） | 共通正本 |
| `SERVICE.md` | サービス固有ルール（スタック表・構成・環境変数） | 雛形から生成 |
| `docs/rules/` | 共通ルール群（本ファイル含む） | 共通正本 |
| `docs/requirements/` | 要件の永続資産（一意ID・negative space。詳細: `docs/rules/requirements.md`） | 骨格配布 |
| `docs/service-rules/` | サービス固有ルール（整合性の具体手順等） | 雛形 |
| `docs/decisions/` | ADR（意思決定記録。運用ガイド＋テンプレ） | 雛形 |
| `.claude/settings.json` | 権限（allow/ask/deny）・フック設定 | 骨格配布 |
| `.claude/scripts/guard-dangerous.sh` | 破壊的操作・秘密読み取りの遮断フック | 骨格配布 |
| `.claude/scripts/session-start-rules.sh` | ルール注入フック | 骨格配布 |
| `.claude/skills/` `.claude/agents/` | skills・サブエージェント | 骨格配布 |
| `.devcontainer/` | 統一開発環境（詳細: `docs/decisions/`） | 骨格配布 |
| `.github/workflows/ci.yml` | CI 多段ゲート（詳細: `docs/rules/quality-gates.md` §4） | 骨格配布 |
| `.editorconfig` | エディタ非依存のスタイル強制（詳細: `docs/rules/code-style.md`） | 骨格配布 |
| `Makefile` | 品質ゲートのターゲット契約（詳細: `docs/rules/quality-gates.md` §1） | 骨格配布 |
| `scripts/pre-push` | push前ゲート（`make audit-all`＋`make test`） | 共通正本 |
| `scripts/commit-msg` | Conventional Commits の機械強制（詳細: `docs/rules/git.md`） | 共通正本 |
| `scripts/check-coverage.sh` | カバレッジのフロア判定（詳細: `docs/rules/quality-gates.md` §5） | 共通正本 |
| `scripts/audit-consistency.sh` | 整合性監査（詳細: `docs/rules/consistency.md`） | 雛形 |
| `scripts/sync-from-common.sh` | 順輸入（共通→サービスの一方通行配布。詳細: `docs/rules/backport.md`） | 共通正本 |
| `.coverage-floor` | カバレッジのフロア値（サービスがラチェット） | 雛形初期値 |
| `.gitignore` `.env.example` `README.md` | 追跡除外・環境変数雛形・入口 | 雛形から生成 |

## プロファイル（新規サービス生成の合成方式）

新規サービス生成は**プロファイル合成方式**（設計の正: `docs/decisions/006-adr-profile-based-bootstrap.md`）。
`profiles/_base/`（共通骨格＝旧 `templates/`）を展開した上に、`--profile` で指定した
`profiles/<name>/` の断片を重ねて配布する。root 正本（`CLAUDE.md`・`docs/rules/` 等、上表「由来: 共通正本」）は
`_base` に複製せず root から直接コピーする（正本の二重管理を避ける）。

```
profiles/
  _base/                  # 共通骨格（全プロファイル共通。単体生成の経路は無い）
  <name>/
    profile.manifest      # 何を追加/置換するかの宣言
    files/<path>          # 追加・置換するファイル実体（生成先の相対パスと同じ配置）
```

### profile.manifest スキーマ

```
# コメントは # で行頭・行末に記述可
profile: <name>         # 必須。ディレクトリ名と一致しないとエラー
description: <一行説明>  # 必須（プロファイル一覧表示に使用）
failclosed_profile: <full-red|display-green>  # 必須。初期fail-closed状態（ADR-006 §7.2。この2種のみ・欠落や他値はエラー）
<op> <path>             # 1行1ファイル。op ∈ {add, replace}
```

- `failclosed_profile`: `full-red`＝全ゲート赤スタート（実装するまでCIは赤）、`display-green`＝表示・
  ビルド系は緑スタート・機微部分は赤のまま。all-green・custom は設けない（理由: ADR-006 §7.2）。
- `add`: 生成先に無いファイルを追加する（既に在ればエラー）。
- `replace`: `_base` 由来の同名ファイルを丸ごと差し替える（無ければエラー）。
- 検証は fail-closed：解釈できない行・絶対パス/`..`/空白を含むパス・`files/` の実体欠落は
  すべて即エラー（exit 2）。黙って読み飛ばさない。
- 適用後、manifest 記載ファイルにも `SERVICE_NAME`/`[サービス名]` のプレースホルダ置換が効く。
- 各プロファイルは目印として `.service-profile`（生成元プロファイル名1行）を add する。
- プロファイル層は**スタック依存物を持ってよいが、ドメイン語は禁止**（ADR-006 §3）。

## 運用

- 新規サービスは `scripts/new-service.sh <名前> --profile <プロファイル>` で上記一式を生成する
  （`--profile` は必須。未指定はエラー＋一覧表示。`_base` の単体指定は不可）。
- 「由来: 骨格配布」は共通リポの `profiles/_base/` から配布され、サービス側とパスが 1:1 対応しないため
  更新は手動同期（基盤 → サービスの一方通行。詳細: `docs/rules/backport.md`）。
- 必須要素を増減したら、`new-service.sh`・`audit-consistency.sh`・本ファイルを同時に更新する
  （一箇所だけ直すとドリフトする）。
