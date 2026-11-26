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
| [research/quadronegro-at-home-audit.md](docs/research/quadronegro-at-home-audit.md) | findings on extending upkeep to the Btrfs/Infisical pool in `~/unraid-at-home` (draft) |
| [research/quadronegro-at-home-design.md](docs/research/quadronegro-at-home-design.md) | candidate declarative design and migration order for those findings (draft) |
| [research/quadronegro-availability-and-threats.md](docs/research/quadronegro-availability-and-threats.md) | member-loss availability, the strict/degraded policy options, and the physical/remote access ladder for the pool (draft) |
| [research/multi-uid-data-access.md](docs/research/multi-uid-data-access.md) | per-uid read-only/read-write access to the shared mount, rootless Podman, NFS/SFTP and the `systemd-homed` question (draft) |
| [research/workload-isolation-and-egress.md](docs/research/workload-isolation-and-egress.md) | per-workload uid/gid, slice and netns isolation for the three data workloads, the escape-to-root boundary, and UPnP/NAT behaviour under container and VM networking (draft) |
| [research/workload-provisioning.md](docs/research/workload-provisioning.md) | one declaration per workload rendering uids, subids, linger, directories, slice, Quadlet units, pool membership and assertions, with a `promnesia` worked example, plus the rolling-build/image-lock promotion model (draft) |
| [research/gpu-and-display-isolation.md](docs/research/gpu-and-display-isolation.md) | accelerated compute and graphical workloads: where the GPU boundary really is, one-GPU contention, and why Linux has no SurfaceFlinger for showing another session's surfaces (draft) |
| [research/cross-host-systemd.md](docs/research/cross-host-systemd.md) | whether a distributed systemd control plane exists, and what fleet and Kubernetes teach (draft) |
| [research/storage-overlay.md](docs/research/storage-overlay.md) | the smallest single-node storage system — abstraction ladder, index authority, what FEC is actually for, and whether k3s or Longhorn helps (draft) |
| [research/microvm-composition.md](docs/research/microvm-composition.md) | how VMs and microVMs compose with the storage design — trust direction, where plaintext lives, the Gondolin/smolvm/krun comparison, TSI versus passt versus TAP, virtio-fs and a FUSE view, nesting and distribution (draft) |
| [research/sharing-and-durability.md](docs/research/sharing-and-durability.md) | the least-vulnerable file-level sharing interface and the `.quadronegro-*` durability marker contract (draft) |
| [research/key-custody.md](docs/research/key-custody.md) | TPM-sealed versus remotely injected credentials, what each protects against a physical adversary, and why cold boot defeats both (draft) |
| [declarative-upkeep.md](docs/declarative-upkeep.md) | the proof-of-concept schema and manifests for steps, asserts, credentials and phases (draft) |

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
