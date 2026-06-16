FROM alpine:3.23

ARG USERNAME=vscode

RUN apk add --no-cache \
    bash \
    curl \
    git \
    openssh-client \
    jq \
    age

RUN adduser -D -s /bin/bash $USERNAME

WORKDIR /workspace
USER $USERNAME