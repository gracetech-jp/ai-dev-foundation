FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    curl git zsh build-essential ca-certificates sudo \
    && rm -rf /var/lib/apt/lists/*

RUN usermod -l node ubuntu \
    && usermod -d /home/node -m node \
    && groupmod -n node ubuntu \
    && echo "node ALL=(root) NOPASSWD:ALL" > /etc/sudoers.d/node \
    && chmod 0440 /etc/sudoers.d/node

USER node
WORKDIR /home/node

RUN curl -fsSL https://claude.ai/install.sh | bash

ENV PATH="/home/node/.claude/local:$PATH"
