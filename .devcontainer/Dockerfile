FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# jq: .claude/scripts/guard-dangerous.sh（PreToolUseフック）がフックJSON入力を解析するために必要
# shellcheck: make lint のゼロ警告ゲートに必要（不在だと lint が fail-closed で失敗する）
# bats: make test のシェルテスト（tests/*.bats）に必要（不在だと test が fail-closed で失敗する）
# iptables/ipset/iproute2/dnsutils: init-firewall.sh（ADR-013 第1層）が使う
RUN apt-get update && apt-get install -y \
    curl git zsh build-essential ca-certificates sudo jq shellcheck bats \
    iptables ipset iproute2 dnsutils \
    && rm -rf /var/lib/apt/lists/*

# sudo は init-firewall.sh の1本だけに絞る（ADR-013）。sudo グループからも外す。
RUN usermod -l node ubuntu \
    && usermod -d /home/node -m node \
    && groupmod -n node ubuntu \
    && gpasswd -d node sudo \
    && echo "node ALL=(root) NOPASSWD: /usr/local/bin/init-firewall.sh" > /etc/sudoers.d/node-firewall \
    && chmod 0440 /etc/sudoers.d/node-firewall

# ファイアウォールはイメージ内の root 所有コピーを実行する（ワークスペース側は実行対象にしない）。
# 基盤リポの追加許可（ntfy.sh）はビルド時に焼き込む。実行時にワークスペースから読ませない。
COPY init-firewall.sh /usr/local/bin/init-firewall.sh
COPY extra-allowed-domains.txt /usr/local/share/extra-allowed-domains.txt
RUN chown root:root /usr/local/bin/init-firewall.sh /usr/local/share/extra-allowed-domains.txt \
    && chmod 0755 /usr/local/bin/init-firewall.sh \
    && chmod 0444 /usr/local/share/extra-allowed-domains.txt

USER node
WORKDIR /home/node

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN curl -fsSL https://claude.ai/install.sh | bash

ENV PATH="/home/node/.local/bin:$PATH"
