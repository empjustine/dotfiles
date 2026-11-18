---
id: spec-standard
type: architecture-design
status: active
title: "Dotfiles — documentation contract and gate"
parent: index
references: [index, goal, system, design, execution-map, decision-log, known-issues]
---

# The documentation contract

Every Markdown file in this tree is a node: it carries a frontmatter block that
names it (`id`), says what role it plays (`type`), where it sits (`parent`) and
what state it is in (`status`). `docs/spec-check.mjs` walks that graph and fails
the lint run when a node breaks the contract, cites a record that does not
exist, links to a file that is gone, or leaves the component inventory out of
step with the tree.

This is the *mechanism* half of DR-035's documentation split (BRD / SRD / TDD /
log), and it deliberately does **not** try to decide whether a document's prose
is still true. Adapted from the spec-graph standard in the owner's
`agentcontainer` repository (DR-042) — kept to the parts this tree can actually
sustain: no module folders, no vendored specs, no task specs.

## The contract

| field | required | rule |
| --- | --- | --- |
| `id` | yes | unique, lowercase kebab-case. Cited by other documents' `references`; an id is an identity, not a filename. |
| `type` | yes | one of the five below, nothing else |
| `status` | yes | one of the five lifecycle words; absence is drift, not a default |
| `title` | yes | one sentence, quoted if it contains a colon-space |
| `parent` | all but the index | `index` — this tree has no modules, so the index is the only legal parent |
| `references` / `depends-on` | optional | lists of **ids**, never paths; every value must resolve to a node |

A value containing `: ` must be quoted, or every YAML reader truncates it there
and the node silently leaves the graph. The gate reports that as
`value-unquoted`.

## Types

| type | what it is | in this tree |
| --- | --- | --- |
| `index` | the graph root: a map, not a content home | `README.md` |
| `goal-and-requirements` | what the environment must do, and where | `docs/requirements.md` |
| `architecture-design` | how it works, why it is built this way, what is expected to run | `docs/system.md`, `docs/design.md`, `docs/execution-map.md`, this file |
| `decision-log` | the dated record log — one file, one node | `DECISIONS.md` |
| `working-list` | a list that is expected to empty itself | `docs/known-issues.md` |

## Lifecycle

| status | meaning |
| --- | --- |
| `draft` | proposed or being written; nothing has to obey it yet |
| `active` | in force — the code is expected to match it |
| `stale` | in force but known to lag the tree |
| `done` | the work it describes is finished |
| `deprecated` | superseded or retired, kept as history |

One word only. The qualifier goes in the body — for a record, a
`- **Status note (date, DR-###):**` bullet; for a living doc, prose.

## The decision log's own contract

`DECISIONS.md` is one node holding many records, so its rules are separate:

- **Shape.** `## DR-NNN | Title | Status | YYYY-MM-DD` (older records carry
  `YYYY-MM`; the gate accepts both).
- **Numbering.** Three digits, unique, **append-only** — a new record takes one
  past the highest number in use, and a hole is never backfilled. A record that
  is superseded keeps its number and gains a status word.
- **Status vocabulary.** `Accepted`, `Accidental`, `Proposed`, `Resolved`,
  `Withdrawn`. Everything the heading cannot hold ("applied", "see DR-041",
  "merge rejected") goes in the body as a note, which is why the heading cell
  may carry a parenthetical.
- **Citations.** Every `DR-NNN` in any document in this tree must be a record in
  the log. The log is the single source for the numbers; the docs are views.
- **Records are not rewritten.** A record stays true to its own moment: a later
  change adds a status note to it rather than editing its decision.

## Rules the gate adds on top of the vocabulary

- **The inventory matches the tree.** Every file under `profile.d/` and
  `shortcuts/tasks/`, plus the top-level scripts, has a row in
  [system.md](system.md) §2 — and no row names a file that no longer exists.
  This is the check that would have caught the 2026-11-18 prune debris.
- **A living document does not name a removed file.** `README.md`,
  `docs/system.md` and `docs/requirements.md` are held to that; `docs/design.md`
  and `docs/execution-map.md` are rationale documents and may discuss what was
  pruned, and the log may always name history.
- **Citations resolve.** `§N` (or `§N.M`) resolves in this document or in the
  one named on the same line / a few lines above, as a link or a backticked
  path; relative links and `#anchor` fragments resolve too.
- **Every document opens with what it is** — a paragraph between the H1 and the
  first `##`, so a reader arriving from a broken link is not dropped into a
  section about something else.

## What the gate checks, and what it does not

`node docs/spec-check.mjs [root]` exits 0 clean, 1 findings, 2 unreadable tree,
and prints `path[:line]: [code] sentence` per finding. Codes:

`frontmatter-missing`, `frontmatter-unterminated`, `value-unquoted`,
`id-missing`, `id-spelling`, `id-duplicate`, `type-missing`, `type-unknown`,
`status-missing`, `status-unknown`, `title-missing`, `parent-missing`,
`parent-not-index`, `edge-unresolved`, `root-missing`, `opening-block-missing`,
`doc-link-unresolved`, `doc-anchor-unresolved`, `section-cite-unresolved`,
`log-missing`, `dr-format`, `dr-numbering`, `dr-status-unknown`,
`dr-unresolved`, `inventory-missing`, `inventory-stale`, `doc-path-stale`.

What it deliberately does **not** decide: whether the chosen `type` is the right
scope judgement, whether a `status` is honest, whether a record's prose still
matches the code, whether an id deserves its name, and whether a claim in the
body is true. Those are reading work, and a gate that guessed them would be
wrong loudly.

## Running it

`./lint.sh` runs it as the last leg, after shfmt/shellcheck and `zsh -n`, and
aggregates its exit status with the others into `report.txt`. Node is required
for that leg (the repo already needs it for `embed.mjs`/`unembed.mjs`); if node
is missing the leg is reported as skipped and the run fails, so a missing gate
cannot pass silently.

```sh
node docs/spec-check.mjs            # whole tree
node docs/spec-check.mjs some/dir   # a subtree, e.g. before a big move
```

## Adding or changing a document

1. Pick the `type` by role, then the `status` it actually has.
2. Write the frontmatter: `id`, `type`, `status`, `title`, `parent: index`,
   and `references` as ids.
3. Do **not** add a row to README's table for every new file — the table lists
   the document set, and discovery is the frontmatter.
4. If it changes a contract or an invariant, update the owning document in the
   same change, and add a record if a choice was made.
5. Run `./lint.sh`.

## Credits

The frontmatter contract, the five types, the five statuses and the finding-code
convention are adapted from the spec-graph standard in the owner's
`agentcontainer` repository (see its `docs/spec-graph-standard.md` and
`docs/spec-check.mjs`). What was dropped: module/submodule nesting, the vendored
spec exemption, `covers`, task specs, and the archive rules — this tree has no
module folders and no ThinkRail tooling (DR-042).
