---
id: research-files-volumes
type: architecture-design
status: draft
title: "Dotfiles — prior-art research: files, mounts and volumes"
parent: index
references: [index, design, decision-log, research-overview, research-upkeep-mapping]
---

# Dotfiles — prior-art research: files, mounts and volumes

This document covers the two declarative layers that could replace the current
directory and volume handling: `tmpfiles.d` for files and directories, and the
Kubernetes/Podman/Quadlet volume model for persistent container data. It ends
with direct answers to the two practical questions: can a Quadlet volume live on
the external disk, and can Quadlet recover from improper container or volume
state and shut down cleanly?

## tmpfiles.d

### What the format provides

Verified in `man/tmpfiles.d.xml`, `man/systemd-tmpfiles.xml` and
`src/tmpfiles/tmpfiles.c`.

| aspect | behaviour |
| --- | --- |
| line shape | `Type Path Mode User Group Age Argument`; C-style escapes; all fields except the argument may be quoted |
| precedence | `/etc/tmpfiles.d` overrides `/run/tmpfiles.d` overrides `/usr/lib/tmpfiles.d`; `CONF_PATHS` also includes `/usr/local/lib/tmpfiles.d`; lexicographic order; the earliest file for the same path wins; a `/dev/null` symlink masks a vendor file |
| ordering | prefix paths before suffix paths; globs after exact paths; fixed order for ACL/xattr/capability operations; otherwise file order |
| modifiers | `!` boot-only, `-` ignore create failure, `=` replace wrong file type, `~` base64 argument, `^` credential argument, `$` purge-safe |
| create/write types | `f`/`f+`, `w`/`w+`, `d`, `D`, `v`, `q`, `Q`, `p`, `L`/`L+`/`L?`, `c`/`c+`, `b`/`b+`, `C`/`C+` |
| adjust types | `z`, `Z`, `t`, `T`, `a`, `A`, `h`, `H`, `k`, `K` |
| remove/clean types | `r`, `R`, `x`, `X`, `e` |
| age | `s/m/h/d/w/ms/us`; `~` one level; `age-by:` timestamp selection; `0` is unconditional cleanup; cleanup takes BSD locks and skips locked entries |
| file content | `f` writes only when the file did not exist; `f+` truncates; `w` only if it exists; `w+` appends; the argument is a short string, newline-terminated for `f`/`w` |
| copy | `C` copies only if the destination is missing or empty; `C+` descends into an existing directory |
| specifiers | `%h`, `%u`, `%U`, `%g`, `%G`, `%C`, `%S`, `%T`, `%V`, `%m`, `%b`, `%H`, `%L`, `%l`, …; paths must be absolute after expansion |
| commands | `--create`, `--remove`, `--clean`, `--purge`, `--user`, `--boot`, `--graceful`, `--dry-run`, `--inline`, `--prefix`, `--exclude-prefix`, `-E`, `--root`, `--image`, `--replace`, `--cat-config` |

### What it does not do

- It does **not** mount filesystems. It can create the mountpoint directory, but
  a `.mount` unit, fstab/automount, `systemd-mount`, or Podman's local volume
  driver has to perform the mount.
- It is **not** a multi-line config-file deployer. `f+` truncates but writes one
  short line; `C` only fills an empty destination. Deploying a file such as
  `/etc/sysctl.d/99-tailscale.conf` is better done with `C+` from a source
  directory, `install`, or a step.
- It has no notion of a container, a job, a service lifetime, or a dependency
  graph. systemd's own guidance is to use `RuntimeDirectory=`,
  `StateDirectory=`, `CacheDirectory=`, `LogsDirectory=` and
  `ConfigurationDirectory=` for service-owned directories, and reserve
  `tmpfiles.d` for lifetimes independent of a service or for more complex
  configuration.

### tmpfiles.d without systemd

`systemd-tmpfiles` is an ordinary executable, not a PID-1 feature. It requires
`/proc` for many operations and refuses to run without it; `--root` prefixes
configuration and operation paths and bypasses NSS by reading the target's
`/etc/passwd` and `/etc/group`; `--image` operates on a disk image and implies
`-E`. The systemd tests and split packages rely on this.

The ecosystem has several implementations of the same format:

- Gentoo's non-systemd path uses `virtual/tmpfiles`: `sys-apps/systemd-utils`
  with the `tmpfiles` USE flag installs the systemd binary and OpenRC setup
  services, while `sys-apps/seedfiles` is a portable reimplementation with
  `seedfiles-setup` and `seedfiles-setup-dev` OpenRC services. The eclass tries
  `systemd-tmpfiles --create`, then `tmpfiles --create`, then
  `seedfiles --create`; the OpenRC service runs
  `systemd-tmpfiles --create --remove --boot --exclude-prefix=/dev`.
- OpenRC's release notes say tmpfiles processing was split out into
  `opentmpfiles`; `bootmisc` only does its own `/tmp` and `/var/run` cleanup.
  OpenRC's `binfmt.d` support is a separate example of reimplementing a systemd
  configuration format as a standalone tool.
- These names are external corroboration, not present in
  `~/Downloads/references/`. Verify the package, version and service name on the
  target distribution before depending on it.

Three packaging examples show why a host without a processor is missing
behaviour:

- Podman installs `contrib/tmpfile/podman.conf` with `x` and `R!` lines for
  `/tmp/podman-run-*`, `/tmp/storage-run-*`, `/tmp/containers-user-*`,
  `/tmp/run-*/libpod`, `D! /var/lib/containers/storage/tmp` and
  `R! /var/tmp/container_images*`. Without a processor, those temporary trees
  accumulate.
- udisks installs `data/tmpfiles.d/udisks2.conf` containing
  `d /run/media 0755 root root`, the parent of the removable-media mountpoints.
- distrobox masks vendor rules (`tmp.conf`, `x11.conf`, `systemd-tmp.conf`,
  `openssh-client.conf`, `tpm-udev.conf`, `tpm2-tss-fapi.conf`) with
  `/dev/null` symlinks because they chown paths bind-mounted from the host.
  That is prior art for both the mask convention and the danger of running
  vendor rules blindly inside a user namespace.
- kind and minikube delete `systemd-tmpfiles-setup.service` from their node
  images; they replace it with image-build-time directory creation.

The practical recommendation is to use the format, not to write an engine:
consume the distribution's `systemd-tmpfiles` where systemd exists, and depend
on one of the portable implementations where it does not. A local subset is
justified only if a non-systemd host with a container runtime appears, and then
it should implement only the line types actually used, with `--dry-run` and the
same precedence rules.

## The Kubernetes PVC model

Verified in `kubernetes/website.git` and `kubernetes/kubernetes.git`.

| concept | behaviour worth copying |
| --- | --- |
| PV/PVC | a PV is the backing resource; a PVC is a namespaced request; binding is one-to-one and exclusive |
| provisioning | static PVs, or dynamic through a StorageClass; an empty class disables dynamic provisioning |
| access modes | `ReadWriteOnce` (a single node, possibly several pods), `ReadOnlyMany`, `ReadWriteMany`, `ReadWriteOncePod` (a single pod; CSI only) |
| reclaim | `Retain`, `Delete`, deprecated `Recycle`; dynamic PVs inherit the class policy, default `Delete` |
| binding | `volumeBindingMode: Immediate` (default) or `WaitForFirstConsumer` for topology-constrained volumes |
| expansion | `allowVolumeExpansion` on the StorageClass |
| local PV | `LocalVolumeSource{Path, FSType}` plus `nodeAffinity`; static and node-pinned |
| templates | StatefulSet `volumeClaimTemplates` plus `persistentVolumeClaimRetentionPolicy{whenDeleted, whenScaled}`; default `Retain` for both |
| ephemeral | `emptyDir` lives with the pod; generic ephemeral volumes create a PVC from `ephemeral.volumeClaimTemplate` and delete it with the pod |
| volume mode | `Filesystem` (default) or `Block` |

For a single host the useful subset is: name, backing path/device, filesystem
type, mount options, single-writer access, reclaim policy, and
first-consumer binding. Capacity, CSI, snapshots, topology and a control plane
are not.

## Podman's PVC-shaped volumes

Verified in `docs/source/markdown/podman-kube-play.1.md.in`, `pkg/util/kube.go`,
`pkg/domain/infra/abi/play.go` and `pkg/specgen/generate/kube/volume.go`.

- `podman kube play` accepts `Pod`, `Deployment`, `PersistentVolumeClaim`,
  `ConfigMap`, `Secret`, `DaemonSet` and `Job`.
- Supported volume sources: `hostPath`, `emptyDir`, `configMap`,
  `persistentVolumeClaim` and `image`.
- A PVC becomes a **named Podman volume**. Only the metadata name, labels and
  annotations are used; the `spec` (capacity, access modes, storage class,
  volume mode, data source) is ignored.
- The annotations are the PVC-to-Podman mapping:
  `volume.podman.io/driver`, `volume.podman.io/device`,
  `volume.podman.io/type`, `volume.podman.io/uid`,
  `volume.podman.io/gid`, `volume.podman.io/mount-options`,
  `volume.podman.io/import-source` and `volume.podman.io/image`.
- Volume creation uses `WithVolumeIgnoreIfExist`: missing volumes are created,
  existing ones are reused, and the options of an existing volume are not
  updated.
- `podman kube down` stops and removes pods and containers; volumes survive
  unless `--force` is used. `kube play --replace` tears down and recreates the
  pods, so it is apply-once with a restart, not a reconciler.
- `Job` is only a pod named `<job>-pod`; `backoffLimit`, `completions` and
  `parallelism` are not implemented. `Deployment` replicas are limited to one
  unless `--multiple-pods`.
- `podman kube generate` turns bind mounts into `hostPath` and named volumes
  into PVCs, but it does not emit the `volume.podman.io/*` annotations, so
  generated YAML loses the device/type/options.

## The local volume driver

Verified in `libpod/runtime_volume_common.go`, `libpod/volume_internal_common.go`
and `libpod/volume_internal.go`.

- Accepted local-driver options: `device`, `o`, `type`, `uid`, `gid`, `size`,
  `inodes`, `noquota`, `copy`, `nocopy`.
- If `type=bind`, the `device` must exist **at create time**. This validation is
  skipped when the bind is expressed only as `o=bind`; that is a real difference,
  not a stylistic one.
- Mounting is lazy. `needsMount()` is true when options are set; on first use
  Podman runs `mount -o <o> [-t <type>] <device> <mountpoint>` (or `-o bind` for
  a bind) and increments `MountCount`.
- Volumes with options are unmounted when the last user releases them;
  `podman volume rm` force-unmounts. Volume state has `MountCount` and
  `MountPoint`, and `resetVolumeState` clears them on the state refresh after a
  reboot, so a stale mount count after reboot is not fatal.
- A wrong existing volume is not reconciled: changing `Device=`, `Type=` or
  `Options=` requires an explicit remove and recreate, or a new volume name.
  Removing a bind-backed volume removes the volume object and mountpoint; the
  external directory and its data remain.

## Quadlet

Verified in `docs/source/markdown/podman-{volume,container,kube,build,image}.unit.5.md.in`
and `pkg/systemd/quadlet/quadlet.go`.

| unit | generated behaviour |
| --- | --- |
| `.volume` | one-shot `podman volume create --ignore` with `Device=`, `Type=`, `Options=`, `Copy=`, `User=`, `Group=`, `VolumeName=`, `Driver=`; `Type=bind` adds `RequiresMountsFor=<device>` and Podman validates the device |
| `.container` | `podman run --name <name> --replace --rm`; `ExecStop=podman rm -v -f -i <name>`; `ExecStopPost=-podman rm -v -f -i <name>`; `KillMode=mixed`; `Delegate=yes`; `Type=notify` with `--sdnotify=conmon` unless `Notify=` says otherwise |
| `.kube` | `podman kube play` as a service; `ExitCodePropagation` defaults to `none`; `KubeDownForce` controls whether `kube down` removes volumes |
| `.build` | one-shot `podman build` with `ImageTag=`, `File=`, `SetWorkingDirectory=`, `Target=`, `Pull=`, `Retry=`; no `--manifest` support |
| `.image` | one-shot image pull with `Image=`, `ImageTag=`, `Policy=`, `Retry=` |

Quadlet passes the `[Install]` section through; it does not add one. A user unit
needs `WantedBy=default.target` (or the appropriate target) to be part of the
boot/shutdown transaction. Quadlet requires systemd and cgroup v2.
`podman auto-update` requires containers to run inside systemd units; it compares
image digests, restarts the unit, and rolls back by default if the restart
fails.

## Answer: can a Quadlet volume live on the external disk?

Yes. The supported form is a `.volume` unit with:

    [Volume]
    VolumeName=syncthing-volume
    Device=/run/media/deck/a95e1c63-2126-4d6c-b682-7dfbc2d1b631/var/lib/syncthing
    Type=bind
    Copy=false

This generates `podman volume create --ignore` with the device and
`type=bind` options. At first use Podman bind-mounts the external
directory onto the volume's `_data` mountpoint. The **data** is on the external
disk. The volume object, its metadata and its mountpoint directory remain in
Podman's graphroot (`~/.local/share/containers/storage/volumes/…` for rootless,
`/var/lib/containers/storage/volumes/…` for rootful), which is small. If even
the mountpoint must be outside home, use a direct
`Volume=/run/media/…:/var/lib/…` bind in `.container` instead of a named volume,
or relocate `graphroot` (not recommended, because images and metadata move too).

This is not a bind "shenanigan"; it is the local driver's documented `type`,
`device` and `o` options. Two details matter:

- Use `Type=bind`, not only `Options=bind`. `Type=bind` makes Podman validate
  that the device exists at volume-create time and makes Quadlet emit
  `RequiresMountsFor=<device>`. `Options=bind` alone skips the validation.
- `RequiresMountsFor=` only orders after **systemd-known** mount units. If the
  external disk is mounted by udisks directly, there may be no `.mount` unit, so
  the edge has nothing to attach to. Use an fstab entry with
  `x-systemd.automount`, a `.mount`/`.automount` unit, or `systemd-mount` so the
  disk is systemd-managed; then the ordering works. A fallback is
  `AssertPathIsMountPoint=` in the unit, which fails loudly if the disk is
  missing, but it does not mount.

SELinux and ownership are unchanged from the current scripts, but they belong
on the **container** mount, not on the volume's host mount:

    [Container]
    Volume=syncthing.volume:/var/lib/syncthing:Z,U

Referencing the `.volume` unit (the `.volume` suffix) is what adds
`Requires=`/`After=` on the volume service; using the bare volume name would
treat it as an ordinary named volume. `:Z` relabels the bind source with the container file type, and `:U`
recursively chowns it. `Options=` in `.volume` is passed to `mount(8)`, so
`Z`/`U` there would be an unknown mount option, not a relabel. Both are fine
for a dedicated data directory, and both are risky on a shared filesystem.
Test with a scratch directory before migrating. Rootless Quadlet
needs `loginctl enable-linger` if the container must run without a login
session; rootful Quadlet lives under `/etc/containers/systemd/` and uses
`/var/lib/containers/storage`.

## Answer: can Quadlet recover from improper state and shut down cleanly?

### Containers

Yes, by construction:

- `podman run --replace` replaces and removes a container with the same name, so
  a leftover container from a crash does not block the next start. This is the
  built-in form of the scripts' "if container exists, stop and remove" guard.
- `--rm` removes the container on a clean exit. `ExecStop` runs
  `podman rm -v -f -i <name>`; `ExecStopPost` runs the same command with a `-`
  prefix so it is ignored when the container is already gone, including when
  conmon died and `ExecStop` never ran.
- `podman rm -f` stops a running container with the container's `StopTimeout`
  (set from Quadlet's `StopTimeout=`, which maps to
  `podman run --stop-timeout=`). It sends SIGTERM, waits, then SIGKILL. That is a controlled
  stop, not an immediate kill, as long as the application handles SIGTERM and
  the timeout is set (30 seconds for syncthing, 60 for transmission, matching
  the containers' current stop-timeout values).
- `KillMode=mixed` and `Delegate=yes` let conmon and the container runtime do
  their job while still cleaning the cgroup if they do not.
- A failing health check is handled by `HealthCmd` plus
  `HealthOnFailure=restart` (or `kill`), not by a job-level predicate. The
  current transmission script's "if healthcheck passes, exit 0" is replaced by
  the health policy and idempotent start.

### Volumes

Partially:

- `podman volume create --ignore` makes creation idempotent. A missing volume is
  created; an existing one is reused.
- Options are immutable after creation. A changed `Device=`/`Type=`/`Options=`
  is not reconciled; you need an explicit maintenance job that stops the
  container, removes the volume, and starts the volume/container again. Removing
  a bind-backed volume unmounts and deletes the volume object, not the external
  data. Do not make that automatic for a volume whose data is the only copy.
- `Type=bind` validation happens at create time, not every start. If the volume
  already exists and the device later disappears, the container mount fails; an
  `AssertPathIsMountPoint=`/`AssertPathExists=` in the unit or a short
  precondition job catches it earlier and more clearly.
- Podman resets `MountCount`/`MountPoint` on the post-reboot state refresh, and
  `podman volume rm` force-unmounts. That covers the common stale-mount case. It
  does not make the volume a reconciler.
- `podman system check --quick --repair` checks image/container storage
  consistency; it is not a volume-state repair tool. Use it rarely and read its
  output.

### Controlled shutdown

With a systemd-managed external mount, the start ordering is:

`container` unit → `volume` unit → `RequiresMountsFor=` → `.mount`/`.automount`
→ device.

The volume unit is a oneshot and is normally inactive after creating the
volume. With a named `.volume`, the mount edge lives on the volume service and
the container orders after the service; if you want the container itself to
carry the mount dependency, add `RequiresMountsFor=<device>` to the
container's `[Unit]` section, or use a direct `Volume=/run/media/…` bind, which
adds it automatically. Podman unmounts the bind when the last container using
it stops. The container's `ExecStop` runs first, and the mount is unmounted
after that. Add `[Install] WantedBy=default.target` (user) or
`multi-user.target` (system) so the unit is in the boot transaction and is
stopped on shutdown. Rootless containers need linger if they must survive
logout. If the disk is udisks-mounted without a systemd mount unit, the
container still stops gracefully, but the container-to-mount ordering is not
enforced; unmounting or unplugging the disk can race the container. That is the
one part of the chain Quadlet cannot supply by itself.

## The two ends of "PVC at home"

- Minimal: kind's default StorageClass is `rancher.io/local-path` with
  `volumeBindingMode: WaitForFirstConsumer`, `reclaimPolicy: Delete`, a
  `nodePathMap` under `/var/local-path-provisioner`, a `setup` script
  (`mkdir -m 0777 -p "$VOL_DIR"`), a `teardown` script (`rm -rf "$VOL_DIR"`)
  and a helper pod. Dynamic provisioning on one node is a naming scheme plus
  mkdir/rm.
- Real: Mayastor is a CSI data plane with a `DiskPool` custom resource, a
  reconciler that re-imports pools after restarts, NVMe-oF, replicas and volume
  targets. That is the cost of HA storage, and it does not belong in a
  dotfiles maintenance DAG.

## Open questions

- Is the external disk managed by fstab/automount, a `.mount` unit, or udisks?
  This decides whether `RequiresMountsFor=` is meaningful or only decorative.
- Does the volume need to be shared by more than one container? If not, a direct
  `Volume=` bind in `.container` is simpler than a named `.volume`.
- Is the data directory dedicated to the container? If not, `:Z`/`:U` must be
  reviewed before copying the current scripts.
- Does a non-systemd host ever run Podman? If not, the tmpfiles subset is not
  needed; if yes, the subset needs the line types from the actual rules, not the
  whole format.
- Should `reclaim` default to `retain` for every bind-backed volume? The
  Kubernetes default for a manually created PV is `Retain`; dynamic PVs default
  to `Delete`. For external-disk data, `retain` is the safer default.
