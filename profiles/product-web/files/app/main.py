"""SERVICE_NAME — FastAPI 最小起動＋DB疎通の参照実装（reference）。

これは「別コンテナの PostgreSQL へ接続確認する作法」を示す参照実装であり、
サービスは本実装で置き換えてよい。業務エンドポイント・認証・モデル定義・
テーブル・マイグレーションは意図的に含めていない（ADR-006 §3.1 ドメイン境界）。
"""

import os

from fastapi import FastAPI
from fastapi.responses import JSONResponse
from sqlalchemy import create_engine, text

app = FastAPI()

# DATABASE_URL は compose が注入する（.devcontainer/compose.yaml / .env.example 参照）。
# pool_pre_ping: 切断済みコネクションを自動検出する（疎通確認用途の定石設定）。
_engine = create_engine(os.environ["DATABASE_URL"], pool_pre_ping=True)


@app.get("/health")
def health() -> JSONResponse:
    """DB へ SELECT 1 を発行し、疎通できれば 200 / 失敗なら 503 を返す。"""
    try:
        with _engine.connect() as conn:
            conn.execute(text("SELECT 1"))
    except Exception:
        return JSONResponse(status_code=503, content={"status": "ng", "database": "unreachable"})
    return JSONResponse(status_code=200, content={"status": "ok", "database": "ok"})
