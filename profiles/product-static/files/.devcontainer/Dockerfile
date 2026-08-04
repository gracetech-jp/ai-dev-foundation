# [profile:product-static] Astro SSG ビルド土台（Node 24 LTS + pnpm 10）。ADR-006 C-2。
# _base の Dockerfile 全文を保持し、Node/pnpm 層のみを追記した置換ファイル（_base 側の改善は手動同期）。
# service: SERVICE_NAME
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# jq: .claude/scripts/guard-dangerous.sh（PreToolUseフック）がフックJSON入力を解析するために必要
# shellcheck: make lint のゼロ警告ゲートに必要（不在だと lint が fail-closed で失敗する）
# iptables/ipset/iproute2/dnsutils: init-firewall.sh（ADR-013 第1層）が使う
RUN apt-get update && apt-get install -y \
    curl git zsh build-essential ca-certificates sudo jq shellcheck \
    iptables ipset iproute2 dnsutils \
    && rm -rf /var/lib/apt/lists/*

# gh: CI 結果と Actions の状態をエージェント自身が確認するために使う（ADR-013 の判断変更）。
# 取得は**ビルド時**なので、実行時の許可リスト（init-firewall.sh）とは無関係に入る。
# 認証は環境変数 GH_TOKEN（fine-grained PAT・Actions:Read + Contents:Read・対象3リポジトリ）を
# devcontainer.json の containerEnv からホスト環境変数経由で渡す。イメージにも git にも焼かない。
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      -o /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update && apt-get install -y gh \
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

# sudo は init-firewall.sh の1本だけに絞る（ADR-013）。sudo グループからも外す。
RUN usermod -l node ubuntu \
    && usermod -d /home/node -m node \
    && groupmod -n node ubuntu \
    && gpasswd -d node sudo \
    && echo "node ALL=(root) NOPASSWD: /usr/local/bin/init-firewall.sh" > /etc/sudoers.d/node-firewall \
    && chmod 0440 /etc/sudoers.d/node-firewall

# ファイアウォールはイメージ内の root 所有コピーを実行する（ワークスペース側は実行対象にしない）
COPY init-firewall.sh /usr/local/bin/init-firewall.sh
RUN chown root:root /usr/local/bin/init-firewall.sh \
    && chmod 0755 /usr/local/bin/init-firewall.sh

USER node
WORKDIR /home/node

RUN curl -fsSL https://claude.ai/install.sh | bash

ENV PATH="/home/node/.claude/local:$PATH"
