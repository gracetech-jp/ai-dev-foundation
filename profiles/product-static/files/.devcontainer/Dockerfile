# [profile:product-static] Astro SSG ビルド土台（Node 24 LTS + pnpm 10）。ADR-006 C-2。
# _base の Dockerfile 全文を保持し、Node/pnpm 層のみを追記した置換ファイル（_base 側の改善は手動同期）。
# service: SERVICE_NAME
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# jq: .claude/scripts/guard-dangerous.sh（PreToolUseフック）がフックJSON入力を解析するために必要
# shellcheck: make lint のゼロ警告ゲートに必要（不在だと lint が fail-closed で失敗する）
RUN apt-get update && apt-get install -y \
    curl git zsh build-essential ca-certificates sudo jq shellcheck \
    && rm -rf /var/lib/apt/lists/*

# Node 24（Active LTS・メジャー固定。マイナーはビルド時最新＝セキュリティパッチ追従。ADR-006 フェーズ2承認）
# Astro 6 の要件（Node >= 22.12）を充足する。Astro 自体は各サービスの package.json で固定する（土台はNode互換のみ保証）。
RUN curl -fsSL https://deb.nodesource.com/setup_24.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# pnpm 10 系（corepack は Node 25+ で同梱廃止決定のため不採用）。
# pnpm 10 は package.json の packageManager フィールドを自動で尊重するため、
# ここはブートストラップの10系のみ導入し、正確なバージョン固定は各サービス側で行う。
RUN npm install -g pnpm@10

RUN usermod -l node ubuntu \
    && usermod -d /home/node -m node \
    && groupmod -n node ubuntu \
    && echo "node ALL=(root) NOPASSWD:ALL" > /etc/sudoers.d/node \
    && chmod 0440 /etc/sudoers.d/node

USER node
WORKDIR /home/node

RUN curl -fsSL https://claude.ai/install.sh | bash

ENV PATH="/home/node/.claude/local:$PATH"
