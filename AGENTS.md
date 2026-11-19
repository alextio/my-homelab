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

## Surface security risks

Whenever the user is considering a change to a service or the cluster (a proposal, a question like "how can I…", or a request to do it), name its security consequences before or alongside the how, not after it's done. The user may not see them otherwise. In particular, call out:

- **Removed or weakened authentication**: what becomes reachable without a login, and from where (the LAN, any pod in the cluster, a Coder workspace).
- **Bypass paths**: a service protected only at the ingress (Traefik, oauth2-proxy) is still open to anything that can reach its Service directly.
- **Who gets what access**: e.g. oauth2-proxy lets every Dex user through, so adding a Dex user grants access to every service behind it.
- **Where secrets and keys live**: new copies of a credential or private key (Bitwarden, Git, another cluster), and who can read them.
- **Blast radius**: what an attacker could do with the thing being exposed (a CA key can mint trusted certs for every device; an admin UI can change DNS for the whole network).

Say how big the risk is and what would mitigate it. Keep it short, and don't block on it: the user decides.

## Git Commit Messages

See [./docs/git-commit-messages.md](docs/git-commit-messages.md).

## Git workflow

- **Never push to `main`.** Work on a branch. Open a PR only if it's truly needed, and only when the user asks for one.
- **No `Co-Authored-By` trailer** (or any other AI attribution line) in commit messages or PR descriptions.
