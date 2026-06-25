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

echo "=== セットアップ完了 ==="
echo "次のステップ: .env を編集してから 'claude' を実行してください"
