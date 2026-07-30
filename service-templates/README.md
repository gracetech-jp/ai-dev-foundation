# service-templates/ — 参照方式版の配布雛形（移行期）

参照方式への移行で「配布物の正本」をここへ移した。現時点では `new-service.sh` がまだ
`profiles/_base/` を読むため、**両方を対で維持している**。将来 `_base` を撤去した時点で
このディレクトリが唯一の雛形になる。

## ディレクトリ構成

```
service-templates/
├── README.md              # このファイル
├── Makefile               # 参照方式版のターゲット契約（common/make/*.mk を include する）
├── PROJECT.md.template    # プロジェクト固有ルールの雛形
├── README.md.template     # 生成物の README 雛形
├── gitignore.template     # 追跡除外の雛形
├── claude/                # Claude Code のガードレール一式（先頭のドットを意図的に外している）
├── docs/                  # docs/service-rules/ 等の雛形
├── scripts/               # プロジェクトが肉付けする監査スクリプトの雛形
└── .devcontainer/         # 統一開発環境の雛形
```

## `claude/`（ドット無し）の理由

`.claude/skills/` というパスが作業ディレクトリ配下にあると、Claude Code がそこを
**スコープ付きスキルとしてオンデマンドに読み込む**（実測）。配布前の雛形が基盤セッションの
スキル一覧へ混ざるのを構造的に防ぐため、先頭のドットを外してある（2026-07-26）。
配布時に `.claude/` へ置き直される。

## `profiles/_base/` との関係

- 対応は `service-templates/claude/...` ↔ `profiles/_base/.claude/...` のようにドットの有無だけずれる。
- **一致を機械強制**する（整合性監査の検査(10)）。片方だけ直すと赤になる。
- ただし参照方式へ**意図的に書き換えた**もの（`Makefile`・`.devcontainer/devcontainer.json`・
  `.github/workflows/ci.yml`・`claude/settings.json`）は不一致が正しい状態として除外している。
  除外を増やすときは理由を検査(10)のコメントに1行残すこと。
