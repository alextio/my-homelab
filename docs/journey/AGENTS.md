# Agent Instructions — docs/journey

Write-ups of homelab work, one file per piece of work. When the user says
"write a report of what we did" (or "write up", "summarize this journey"),
write it here in the format below. [20261120-lets-encrypt-via-duckdns.md](20261120-lets-encrypt-via-duckdns.md)
is the worked example.

## File

- Name: `YYYYMMDD-<kebab-case-topic>.md`, e.g.
  `20261120-lets-encrypt-via-duckdns.md`. The date is when the work was
  done: the date of its last commit, or today if nothing was committed. Files
  sort by date, so no sequence number.
  - The `NNN-` (`001-`…`003-`) and `00x-` files are from the old numbered
    scheme. Leave their names alone, and don't number new files.
- Markdown (`.md`). Older files are `.mdx`; leave them as they are.
- Audience: the user months from now, and anyone reading the repo who wants
  the reasoning, not just the diff. Explain terms a homelab reader might not
  know the first time they appear.

## Sections, in this order

1. **`# <Title>`** plus one or two sentences on why the work took the shape it
   did (e.g. "what looked like a URL change turned into…").
2. **`## What we set out to do`**: the starting state and the goal, including
   the constraint that shaped it (e.g. "nothing exposed to the internet").
3. **`## Where we ended up`**: short bullets describing the final state.
4. **`## Gotchas`**: one numbered `###` heading per surprise, each saying what
   we didn't expect, why it mattered, and its security consequence if it has
   one. Put the gotchas the user names first, in their words, then the rest.
   Group trivial ones under a final `### Smaller ones`.
5. **`## Key decisions`**: a `Decision | Why` table. Include the
   alternatives considered and not taken, and the mitigations accepted for
   now, so a later reader doesn't redo the evaluation.
6. **`## Commits`**: per repo (`03-argocd-kubernetes`, `02-ansible`, the
   parent repo), the commit range (`<base>..<last>`) and a `Commit | What`
   table. Then list anything uncommitted, reverted, or done outside Git (UI
   changes, live AdGuard rewrites).
7. **`## Still to do`**: open follow-ups, TODOs left in the code (with file
   path), and known breakage found along the way, even if it predates the
   work.

## Rules

- **Facts come from the repo and cluster, not memory.** Take commit hashes,
  subjects and ranges from `git log`. If the conversation corrected something
  (a wrong assumption, a note that was fixed), report the corrected version
  and say what changed if it affected a decision.
- **No secrets.** No tokens, passwords, Bitwarden UUIDs, or pasted logs that
  could carry them. Internal LAN IPs and hostnames are fine.
- **Links** are relative: to files in this folder (`001-setup-homepage.mdx`)
  or to repo paths. Name the repo when a path is inside a submodule.
- **Keep it a summary.** Explain the reasoning; don't paste full manifests or
  command transcripts. A short snippet is fine when it is the point.
- Don't edit the other journey files, and don't commit unless asked. Commit
  messages follow [../git-commit-messages.md](../git-commit-messages.md).
