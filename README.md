---
id: index
type: index
status: active
title: "dotfiles — index"
references: [goal, system, design, execution-map, decision-log, known-issues]
---

# dotfiles

One predictable shell environment for one owner across every host and shell
that matters: POSIX desktops, WSL2, Termux, cloud shells. Four rc files that are
copies of one POSIX entrypoint, one drop-in directory (`profile.d/`) behind it,
and a documentation set that is checked mechanically. Native Windows shells are
out of scope (DR-038) — WSL2 is the supported way to run this on a Windows host.

This file is an index, not a content home (DR-035).

## Documents

| document | the question it answers |
| --- | --- |
| [requirements.md](docs/requirements.md) | what the environment must do, and where (BRD) |
| [system.md](docs/system.md) | how it works: components, startup chains, the `profile.d/` contract (SRD) |
| [design.md](docs/design.md) | why it is built this way, grouped by decision |
| [execution-map.md](docs/execution-map.md) | what is expected to run, where, in what order, at what cost |
| [DECISIONS.md](DECISIONS.md) | the dated decision log — the single source for every DR-### cite |
| [known-issues.md](docs/known-issues.md) | documentation drift that is known and not yet fixed |
| [spec-standard.md](docs/spec-standard.md) | the frontmatter contract over these files, and the gate that enforces it |
| [research/overview.md](docs/research/overview.md) | prior-art research and reuse options for declarative upkeep (draft) |
| [research/guards-and-steps.md](docs/research/guards-and-steps.md) | guards, typed conditions, and serial step semantics (draft) |
| [research/files-and-volumes.md](docs/research/files-and-volumes.md) | tmpfiles, Kubernetes PVCs, Podman volumes, Quadlet and out-of-home storage (draft) |
| [research/upkeep-mapping.md](docs/research/upkeep-mapping.md) | the concrete mapping from the current upkeep scripts to steps and volumes (draft) |
| [research/termux-orchestration.md](docs/research/termux-orchestration.md) | which orchestration hypotheses survive on Termux/Android, measured (draft) |
| [research/unraid-at-home-audit.md](docs/research/unraid-at-home-audit.md) | findings on extending upkeep to the Btrfs/Infisical/unraid-at-home hodgepodge (draft) |
| [research/unraid-at-home-design.md](docs/research/unraid-at-home-design.md) | candidate declarative design and migration order for those findings (draft) |

## Use

Install — this is what `deploy.sh` automates (it also scaffolds the Termux:Widget
directories and copies the background tasks on Termux):

```sh
for target in ~/.bash_profile ~/.bashrc "${ZDOTDIR:-$HOME}/.zprofile" "${ZDOTDIR:-$HOME}/.zshrc"; do
	cp "${DOTFILES:-$HOME/dotfiles}/src-dotfiles.sh" "$target"
done
```

Lint — shell formatting and analysis plus the documentation gate:

```sh
./lint.sh
```

It truncates `report.txt` per run and exits non-zero on any finding: shfmt and
shellcheck over `*.sh`/`*.bash`, `zsh -n` over `*.zsh`, and
`node docs/spec-check.mjs` over the Markdown.

## credits

*None currently bundled — the last third-party component (rcaloras'
bash-preexec, MIT) was removed with the atuin ≥ 18.18 floor (DR-037);
see DR-010/DR-025 for its history.*
