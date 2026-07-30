# common/ — 共通資産の実体

各プロジェクトが**参照する**共通資産の置き場。ここにあるものはプロジェクト側へ複製しない
（2026-07-30 順輸入廃止・ADR-010。所有と参照の考え方: `docs/rules/common-assets.md`）。

## ディレクトリ構成

```
common/
├── README.md   # このファイル
├── make/       # Makefile の共通断片（ターゲット契約とゲート呼び出し）
├── scripts/    # ゲート実装と git フックの実体
└── docker/     # devcontainer ベースイメージの正本
```

| パス | 役割 |
|---|---|
| `make/contract.mk` | 品質ゲートのターゲット契約（`all` と `install-hooks` を定義。詳細: `docs/rules/quality-gates.md` §1） |
| `make/gates.mk` | `req-coverage` / `tier-tripwire` / `coverage-floor` の実装。`common/scripts/` を呼ぶ |
| `docker/Dockerfile.base` | devcontainer ベースイメージ。`profiles/_base/.devcontainer/Dockerfile` と対で維持する |
| `scripts/resolve-common.sh` | 共通リポのルートを解決する唯一の起点（マーカーを上方探索） |
| `scripts/pre-push` `scripts/commit-msg` | git フック（`make install-hooks` が `ln -sf` する） |
| `scripts/check-coverage.sh` | カバレッジのフロア判定（一方向ラチェット） |
| `scripts/check-requirements-coverage.sh` | 要件↔テストの被覆検証（未カバー・dangling 検出） |
| `scripts/check-tier-tripwire.sh` | Tier デスカレーションのコード実態からの裏取り |

`scripts/` の共通作法: **fail-closed**（設定が無い・解決できないときは緑にせず非ゼロで終わる）、
**検証対象のルートは引数で受け取る**（スクリプト位置から導出すると共通側から各プロジェクトを
検証できない）、既定値を持たない（機微の定義・マーカー規約はプロジェクトが `Makefile` で渡す）。

## プロジェクトからの参照のされ方

解決の起点はマーカー `.ai-dev-foundation-root` の上方探索。プロジェクトは共通リポの
`projects/` 配下に置く必要がある（外に出すと解決に失敗し `make` が即エラー＝fail-closed）。

- **Makefile**: `include $(COMMON_ROOT)/common/make/{contract,gates}.mk`
- **git フック**: `make install-hooks` が `.git/hooks/` から `common/scripts/` へ `ln -sf`
- **CI**: 共通リポが checkout されないため、`.github/actions/` の composite action を `uses:` で参照する
  （同梱スクリプトは `common/scripts/` の複製。ずれは整合性監査の検査(10)が機械検出する）

## 変更するとき

ここを直せば全プロジェクトに即座に効く（取り込み作業は不要）。逆に、壊す変更を入れると
全プロジェクトが同時に赤になる。基盤の `make all`（bats + 整合性監査）を通してから変更すること。
