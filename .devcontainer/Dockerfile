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

# sudo は init-firewall.sh の1本だけに絞る（ADR-013）。sudo グループからも外す。
RUN usermod -l node ubuntu \
    && usermod -d /home/node -m node \
    && groupmod -n node ubuntu \
    && gpasswd -d node sudo \
    && echo "node ALL=(root) NOPASSWD: /usr/local/bin/init-firewall.sh" > /etc/sudoers.d/node-firewall \
    && chmod 0440 /etc/sudoers.d/node-firewall

# ファイアウォールはイメージ内の root 所有コピーを実行する（ワークスペース側は実行対象にしない）。
# 基盤リポの追加許可はビルド時に焼き込む（実行時にワークスペースから読ませない）。
# 2026-08-04 時点で追加は0件。ファイルは空でも COPY 対象として残す（詳細は当該ファイルのコメント）。
COPY init-firewall.sh /usr/local/bin/init-firewall.sh
COPY extra-allowed-domains.txt /usr/local/share/extra-allowed-domains.txt
# 私的状態と共通資産の分離（ADR-013）。ファイアウォールと同じ理由でイメージ内の root 所有コピーを
# 実行する——ワークスペース側を実行対象にすると、書き換えてから走らせる経路が残る。
COPY setup-claude-config.sh /usr/local/bin/setup-claude-config.sh
RUN chown root:root /usr/local/bin/init-firewall.sh /usr/local/bin/setup-claude-config.sh /usr/local/share/extra-allowed-domains.txt \
    && chmod 0755 /usr/local/bin/init-firewall.sh /usr/local/bin/setup-claude-config.sh \
    && chmod 0444 /usr/local/share/extra-allowed-domains.txt

USER node
WORKDIR /home/node

# Claude Code の私的状態（認証情報・履歴・セッション）を置く名前付きボリュームのマウント先。
# **イメージ内に node 所有で先に作っておく**: Docker は空の名前付きボリュームを
# マウント先の内容と所有者で初期化するため、ここが無いと root 所有で作られ、
# 非 root の node が書けなくなる（ADR-013）。
RUN mkdir -p /home/node/.claude-state

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN curl -fsSL https://claude.ai/install.sh | bash

ENV PATH="/home/node/.local/bin:$PATH"
