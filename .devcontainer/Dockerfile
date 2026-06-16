FROM alpine:3.23


RUN apk add --no-cache \
    bash \
    curl \
    git \
    openssh-client \
    jq \
    age

ARG USERNAME=vscode
RUN adduser -D -s /bin/bash $USERNAME

WORKDIR /workspace
USER $USERNAME