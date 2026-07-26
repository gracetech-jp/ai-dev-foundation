#!/bin/bash
set -e
echo "=== 開発環境セットアップ開始 ==="

# .envファイルがなければexampleからコピー
if [ ! -f /workspace/.env ]; then
  if [ -f /workspace/.env.example ]; then
    cp /workspace/.env.example /workspace/.env
    echo "✅ .env.example から .env を作成しました。値を設定してください。"
  fi
fi

# git フック（pre-push・commit-msg）を導入する。
# 「push前フックとCIの二重ゲート」（quality-gates.md §4）を手動実行に頼らず生成時から有効にするため。
if [ -d /workspace/.git ]; then
  make -C /workspace install-hooks || echo "⚠️ フック導入に失敗しました。'make install-hooks' を手動実行してください"
else
  echo "⚠️ git リポジトリが未初期化です。'git init' 後に 'make install-hooks' を実行してください"
fi

echo "=== セットアップ完了 ==="
echo "次のステップ: .env を編集してから 'claude' を実行してください"
