# 整合性チェック 具体手順・自動チェック（ai-dev-foundation 固有）

> このファイルは**このリポジトリ（基盤リポ自身）に固有**。原則・枠組みは共通の `docs/rules/consistency.md` を正とし、
> ここには基盤リポの実体に依存する**具体コマンド・監査スクリプトの中身・層の呼称**だけを書く。
> 配布の対象外（`docs/service-rules/` はリポに閉じる。詳細: `docs/rules/backport.md`）。
> 基盤リポは自らのルールを dogfood するため、サービスと同じ型でこのファイルを持つ（配布雛形: `profiles/_base/docs/service-rules/consistency.md`）。

---

## このリポジトリの層構成（`docs/rules/consistency.md`「層間チェック」の具体）

基盤リポはアプリを持たないため、「データモデル → 入出力スキーマ → ビジネスロジック → 公開I/F」を
配布基盤の実体に対応づける。

| 層 | このリポでの呼称 | 場所（ディレクトリ／ファイル） |
|---|---|---|
| データモデル | 該当なし（DB非依存） | — |
| 入出力スキーマ | profile.manifest スキーマ・要件front-matter | `profiles/*/profile.manifest`（正: `docs/rules/repo-layout.md`）・`docs/rules/requirements.md` §2 |
| ビジネスロジック | 配布・検証スクリプト | `scripts/*.sh`・`.claude/scripts/*.sh` |
| 公開インターフェース | 配布骨格・共通ルール正本 | `profiles/`・`docs/rules/`・`CLAUDE.md` |

---

## 具体コマンド（`make audit-all` / `make test` の中身）

| 層 | 目的 | このリポでの実コマンド |
|---|---|---|
| (1) 軽量grep整合性 | 参照切れ・配布漏れ・退化・同期漏れの検出 | `bash scripts/audit-consistency.sh`（内訳は下記） |
| (2) 構造的不変条件 | 配布シェル資産の構文・挙動の検証 | `make test`（`bash -n` 構文検査＋ `bats tests/` 全スイート） |
| (3) スキーマdrift | 実データモデルとマイグレーションのズレ検証 | 該当なし（DB非依存） |

- **`scripts/audit-consistency.sh` の検査層**: (1) ドキュメントのリンク切れ／(2) Makefile ターゲット契約／
  (3) 新サービスへの配布漏れ・トレーサビリティ配線退化・基盤CI存在／(4) リネーム残渣（データ駆動）／
  (5) Dockerfile の jq 二重管理／(6) 配布複製の root↔`profiles/_base` 同期。
- **モデル↔マイグレーション drift 検出**: 該当なし（DB非依存）。
- **テスト実行**: `make test` が `bash -n`（全配布シェル資産）と `bats tests/`
  （guard-dangerous / new-service / req-coverage / tier-tripwire / audit-consistency）を実行する。

---

## リネーム残渣スキャン（データ駆動）の登録簿

このリポは `scripts/audit-consistency.sh` 内の `renames` 配列（検査層(4)）を台帳の正とする。
リネームのたびに配列へ `"旧名|新名"` を1行追加する（md の表とスクリプトの二重管理を避けるため、ここには複製しない）。

---

## このリポジトリ固有の整合性チェック項目

- 配布漏れ: `scripts/new-service.sh` の配布物と `docs/rules/repo-layout.md` の必須構成の突合（検査層(3)）。
- 配布複製の同期: `.claude/`（guard・session-start・skills・agents・settings の permissions）が
  root と `profiles/_base/` で一致すること（検査層(6)。`.backport-manifest` 注1の手動同期を機械検証。
  共通所有ロックの deny は _base 側にのみ置く配布分岐として検査側で差し引く。ADR-009）。
- profiles の骨格を変更したら既存サービスへは手動同期で配る（一方通行。ADR-009）。該当プロファイルの
  bats（`tests/new-service.bats`）が緑であることを確認する。
