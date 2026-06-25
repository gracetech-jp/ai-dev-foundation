# ADR-001: devcontainerによる開発環境統一

## 日付
2026-06-25

## ステータス
採用済み

## 背景
チームメンバーのOS環境がWindowsとMacに混在しており、
環境差異によるトラブルが発生しやすい状況だった。

## 決定
VS Code devcontainerを使用し、全員が同一のLinux（Ubuntu 24.04）
コンテナ内で開発を行う。

## 理由
- OS差異（パス区切り・改行コード・ツールバージョン）を完全に吸収できる
- `git clone` → `Reopen in Container` だけで環境が再現できる
- Docker Desktopは使わずWSL2内のDocker Engineを使うことで無料・高速を実現

## 注意事項
- Ubuntu 24.04はUID/GID 1000の`ubuntu`ユーザーが既存のため、
  `groupadd`/`useradd`ではなく`usermod`でリネームする方式を採用
- Windowsでは`${localWorkspaceFolder}`を使うことでパスのハードコードを回避
- プロジェクトは`/mnt/c/`ではなくWSL2ファイルシステム内（`~/projects/`）に置く

## 結果
全メンバーが同一環境で開発可能になり、
「自分の環境では動く」問題が解消される。
