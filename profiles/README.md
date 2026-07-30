# profiles/ — 新規プロジェクト生成の雛形（プロファイル合成方式）

`scripts/new-service.sh` が `_base/`（全プロファイル共通の骨格）を展開し、その上に
`--profile` で指定したプロファイルの断片を重ねて生成する
（設計の正: `docs/decisions/006-adr-profile-based-bootstrap.md`。スキーマ: `docs/rules/repo-layout.md`）。

**共通資産（`CLAUDE.md`・`docs/rules/`・共通スクリプト）はここに置かない。** 生成物は複製を持たず、
実行時に共通リポを参照する（2026-07-30 順輸入廃止・ADR-010）。

## ディレクトリ構成

```
profiles/
├── README.md         # このファイル
├── _base/            # 全プロファイル共通の骨格（単体で生成する経路は無い）
├── product-static/   # 静的サイト向け（Astro SSG + Cloudflare Pages。display-green）
└── product-web/      # 動的Webアプリ向け（FastAPI + PostgreSQL。full-red）
```

各プロファイルの中身は `profile.manifest`（何を add / replace するかの宣言）と
`files/<生成先と同じ相対パス>`（実体）の2つだけ。

## 初期 fail-closed 状態（`failclosed_profile`）

| 値 | 意味 | 採用 |
|---|---|---|
| `full-red` | 生成直後は全ゲートが赤。実装するまで CI は緑にならない | `product-web` |
| `display-green` | 表示・ビルド系は緑スタート、機微部分は赤のまま | `product-static` |

`all-green` と `custom` は設けない（理由: ADR-006 §7.2）。分類し忘れを防ぐため manifest の必須キー。

## 変更するときの注意

- `_base/` を直したら **`service-templates/` 側と対で維持**する。参照方式へ書き換えた雛形
  （`Makefile`・`ci.yml`・`devcontainer.json`・`claude/settings.json`）だけは意図的に不一致にしてよく、
  それ以外は整合性監査の検査(10)が `diff` で一致を機械強制する。
- `_base/.claude/` は root の `.claude/` と対。ずれると**新規プロジェクトだけが古いガードで生まれる**ため、
  検査(6)が一致を強制する（ロック deny だけは配布側にのみ置く意図的な差分）。
- 必須要素を増減したら `new-service.sh`・`audit-consistency.sh`・`docs/rules/repo-layout.md` を同時に直す。
