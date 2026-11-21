# Agent Instructions — docs/plan

The roadmap: improvements we intend to make. [docs/journey/](../journey/)
records work that is done; this folder records work that isn't yet.

## Layout

- **[README.md](README.md)** is the roadmap: one line per item, grouped by
  horizon. It is the only file every item appears in.
- **`<topic>.md`**: a design note for an item that needs one (several
  options, a security trade-off, open questions). Most items don't need one.
  Name it by topic in kebab case, with no date or number: plans move, and the
  date belongs to the journey write-up when the work is done.

## README.md

Sections, in this order:

1. **Now**: being worked on, or next up.
2. **Next**: decided, not started.
3. **Later**: ideas and things waiting on something else (hardware, another
   item). Say what it waits on.
4. **Housekeeping**: merges, commits and cleanups left over from past work.
   They aren't improvements, but they shouldn't get lost.

Each item is one bullet: **bold short title**, one sentence on what and why,
then links: the design note if there is one, and `from:` the journey
write-up it came from. Keep any `TODO(...)` tag and file path from the code.

## Design notes

Sections, in this order:

1. **`# <Title>`**, then `Status: idea | planned | in progress` and
   `Depends on:` (other items, hardware), if anything.
2. **`## Why`**: the problem and what it costs to leave it.
3. **`## Options`**: each option with its trade-offs; mark the preferred one.
4. **`## Security`**: what becomes reachable, who gets access, where secrets
   live, blast radius (see the root [AGENTS.md](../../AGENTS.md)). Write
   "none" only if you checked.
5. **`## Open questions`**.

## When an item is done

Write the journey report (see [../journey/AGENTS.md](../journey/AGENTS.md)),
then remove the item from README.md and delete its design note. The journey
report carries the reasoning from then on, so don't keep a "done" list here.
Add the report's "Still to do" items to README.md.

## Rules

- Facts come from the repo and cluster, not memory. Before seeding an item
  from a journey write-up, check it is still open (branch unmerged, TODO
  still in the code).
- No secrets, same as the journey files.
- Don't commit unless asked. Commit messages follow
  [../git-commit-messages.md](../git-commit-messages.md).
