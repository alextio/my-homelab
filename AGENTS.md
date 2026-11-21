# Agent Instructions — homelab

This repo provisions a Proxmox homelab using **OpenTofu** with a GitOps workflow (Argo CD). Rules specific to each part live next to the code; read the relevant file before editing there.

See [ARCHITECTURE.md](ARCHITECTURE.md) for the repository layout.

## Per-directory instructions

- [01-opentofu/AGENTS.md](01-opentofu/AGENTS.md) — OpenTofu/Proxmox: apply confirmation, state files, SSH agent, verification, VM/LXC ID ranges.
- [02-ansible/CLAUDE.md](02-ansible/CLAUDE.md) — Ansible playbooks (separate repo/submodule).
- [03-argocd-kubernetes/AGENTS.md](03-argocd-kubernetes/AGENTS.md) — Argo CD: sync waves, IP allocations, ExternalSecrets, Reloader opt-ins.
- [.devcontainer/AGENTS.md](.devcontainer/AGENTS.md) — dev container build verification.
- [docs/journey/AGENTS.md](docs/journey/AGENTS.md) — write-ups of past work. When the user says "write a report of what we did", read this first and write the report there in its format.
- [docs/plan/AGENTS.md](docs/plan/AGENTS.md) — the roadmap of future improvements. When a journey report has "Still to do" items, add them to the roadmap; when a roadmap item is done, remove it.

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

This applies to all three repos (this one, `02-ansible`, `03-argocd-kubernetes`); `main` is protected in each.

- **Never push to `main`.** Work on a branch, push it, and open a PR yourself once the change is done; you don't need to be asked.
- **Never merge a PR.** The user merges. In `03-argocd-kubernetes`, merging deploys (Argo CD syncs `main`), so merging is the user's go/no-go.
- **Run `pre-commit run --all-files` before pushing** where the repo has a `.pre-commit-config.yaml`. CI runs the same checks.
- **Put the evidence CI can't produce in the PR body.** CI has no access to the LAN, so it only checks code statically. Paste what you verified locally: the `tofu plan` summary for `01-opentofu` changes, `--check --diff` output for Ansible, the rendered manifest diff for Argo CD.
- **Watch CI after opening a PR** and fix failures before handing back. Don't hand back a PR with red checks without saying why.
- **Submodules:** open and get the submodule PR merged first, then open a PR here that bumps the pointer. The `submodules` check fails if a pointer names a commit that isn't on that repo's `main`.
- **Don't apply or run against live infrastructure** (`tofu apply`, playbooks without `--check`) as part of a PR; that still needs explicit confirmation (see [01-opentofu/AGENTS.md](01-opentofu/AGENTS.md)).
- **No `Co-Authored-By` trailer** (or any other AI attribution line) in commit messages or PR descriptions.
