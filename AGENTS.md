# Agent Instructions — homelab

This repo provisions a Proxmox homelab using **OpenTofu** with a GitOps workflow (Argo CD). Rules specific to each part live next to the code; read the relevant file before editing there.

See [ARCHITECTURE.md](ARCHITECTURE.md) for the repository layout.

## Per-directory instructions

- [01-opentofu/AGENTS.md](01-opentofu/AGENTS.md) — OpenTofu/Proxmox: apply confirmation, state files, SSH agent, verification, VM/LXC ID ranges.
- [02-ansible/CLAUDE.md](02-ansible/CLAUDE.md) — Ansible playbooks (separate repo/submodule).
- [03-argocd-kubernetes/AGENTS.md](03-argocd-kubernetes/AGENTS.md) — Argo CD: sync waves, IP allocations, ExternalSecrets.
- [.devcontainer/AGENTS.md](.devcontainer/AGENTS.md) — dev container build verification.

## Never commit secrets
`.env` files, API tokens, SSH private keys, and files with real credentials must never be staged or committed. Check `git diff --cached` before any commit.

## Standing instructions from the user

When the user says "make sure ..." (e.g. "make sure to not default to X"), treat it as a durable rule: add it as an instruction to the relevant `AGENTS.md` in addition to doing what was asked.

## Git Commit Messages

See [./docs/git-commit-messages.md](docs/git-commit-messages.md).

## Git workflow

- **Never push to `main`.** Work on a branch. Open a PR only if it's truly needed, and only when the user asks for one.
- **No `Co-Authored-By` trailer** (or any other AI attribution line) in commit messages or PR descriptions.
