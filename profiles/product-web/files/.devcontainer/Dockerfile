# [profile:product-web] FastAPI + PostgreSQL 土台（Python 3.14 + uv 0.11）。ADR-006 C-3。
# _base の Dockerfile 全文を保持し、uv/Python 層のみを追記した置換ファイル（_base 側の改善は手動同期）。
# PostgreSQL は同居させない（compose で別コンテナ。.devcontainer/compose.yaml / ADR-006 §7.1）。
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

# uv 0.11.30（バージョン固定インストーラ。ADR-006 フェーズ3承認）。
# Python は apt ではなく uv が導入し、バージョンの正は配布する .python-version（3.14系）に置く。
RUN curl -LsSf https://astral.sh/uv/0.11.30/install.sh | sh \
    && /home/node/.local/bin/uv python install 3.14

ENV PATH="/home/node/.claude/local:/home/node/.local/bin:$PATH"
