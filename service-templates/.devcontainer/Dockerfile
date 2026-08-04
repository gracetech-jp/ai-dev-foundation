FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# jq: .claude/scripts/guard-dangerous.sh（PreToolUseフック）がフックJSON入力を解析するために必要
# shellcheck: make lint のゼロ警告ゲートに必要（不在だと lint が fail-closed で失敗する）
# iptables/ipset/iproute2/dnsutils: init-firewall.sh（ADR-013 第1層）が使う
RUN apt-get update && apt-get install -y \
    curl git zsh build-essential ca-certificates sudo jq shellcheck \
    iptables ipset iproute2 dnsutils \
    && rm -rf /var/lib/apt/lists/*

# sudo は init-firewall.sh の1本だけに絞る（ADR-013）。
# 無制限の NOPASSWD:ALL を残すと、コンテナ内から `sudo iptables -F` でファイアウォールを
# 解除できてしまい、第1層が自己申告になる。
# sudo グループからも外す: ubuntu:24.04 の既定ユーザーは sudo グループに属しており、
# /etc/sudoers の `%sudo ALL=(ALL:ALL) ALL` が残る。パスワード未設定で事実上通らないとはいえ、
# 「効いていないはずのルール」を残さない（fail-closed の原則）。
RUN usermod -l node ubuntu \
    && usermod -d /home/node -m node \
    && groupmod -n node ubuntu \
    && gpasswd -d node sudo \
    && echo "node ALL=(root) NOPASSWD: /usr/local/bin/init-firewall.sh" > /etc/sudoers.d/node-firewall \
    && chmod 0440 /etc/sudoers.d/node-firewall

# ファイアウォールは**イメージ内の root 所有コピー**を実行する。マウントされたワークスペース側の
# ファイルを sudo 実行する構成にすると、書き換えてから sudo する経路が root 昇格になる。
COPY init-firewall.sh /usr/local/bin/init-firewall.sh
RUN chown root:root /usr/local/bin/init-firewall.sh \
    && chmod 0755 /usr/local/bin/init-firewall.sh

USER node
WORKDIR /home/node

RUN curl -fsSL https://claude.ai/install.sh | bash

ENV PATH="/home/node/.claude/local:$PATH"
