FROM ubuntu:24.04

ARG USERNAME=vscode

ENV DEBIAN_FRONTEND=noninteractive

# libatomic1: nvm's Node.js binaries link against it (02-ansible's nodejs role).

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    zsh \
    ca-certificates \
    curl \
    git \
    openssh-client \
    jq \
    age \
    sudo \
    vim \
    gnupg \
    unzip \
    libatomic1 \
    && rm -rf /var/lib/apt/lists/*


RUN userdel -r ubuntu \
    && useradd -m -u 1000 -s /bin/zsh $USERNAME \
    && echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/$USERNAME

WORKDIR /workspace
USER $USERNAME
