FROM ubuntu:24.04

ARG USERNAME=vscode

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    ca-certificates \
    curl \
    git \
    openssh-client \
    jq \
    age \
    sudo \
    vim \
    gnupg \
    && rm -rf /var/lib/apt/lists/*


RUN userdel -r ubuntu \
    && useradd -m -u 1000 -s /bin/bash $USERNAME \
    && echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/$USERNAME

WORKDIR /workspace
USER $USERNAME