---
id: research-multi-uid-access
type: architecture-design
status: draft
title: "Multi-uid access to the quadronegro data mount"
parent: index
references: [index, research-quadronegro-design, research-quadronegro-audit, research-files-volumes, declarative-upkeep-poc]
---

# Multi-uid access to the quadronegro data mount

This note answers the access questions that follow from the declarative
quadronegro shape: whether a mount under the immutable Fedora atomic root is
usable, how per-workload uids (for example `u0_a200` at uid 10200) get
read-only and read-write views of one Btrfs filesystem, whether the same
segmentation works over NFS and SFTP, and whether `systemd-homed` is the
right mechanism. It is a draft design note, not an installed change.

The companion documents are [the candidate quadronegro design](quadronegro-at-home-design.md),
[the audit](quadronegro-at-home-audit.md), [files and volumes](files-and-volumes.md)
and [the declarative proof of concept](../declarative-upkeep.md).

## Current state and target

Today the mount is reachable only by uid 1000 (`deck`). Workloads run either
as rootful Docker or as rootless Podman under that same uid. Rootful Docker is
root-equivalent by construction; rootless Podman under one uid separates the
container from the host root but not the workload from the other workloads,
because they share the uid and therefore share every DAC decision.

The target is an Android-like split: one host identity per workload
(`u0_a200` at uid 10200), each with its own rootless Podman storage for
"trusted" work, and a VM or microVM for work that is exposed or not trusted.
The split is useful only if the shared data mount is segmented in the same
unit of trust.

## The mount point on an immutable composefs host

On Fedora atomic (Silverblue, Bazzite) the root is a read-only composefs
image. `/usr` is read-only, `/etc` and `/var` are writable and persistent,
and `/run` is a tmpfs. Mounting a filesystem is not blocked by the read-only
root, and a system mount unit creates its mount point even on tmpfs (systemd
calls `mkdir_p_label` before mounting). `/run/media/quadronegro` therefore works,
but it is the wrong home for persistent shared data:

- every `/run` directory is recreated at boot, so ownership, mode, SELinux
  label and any export path are boot-local;
- `/run/media` is the udisks namespace (`/run/media/$USER/$UUID`); a second
  owner for the same path is confusing even when it works;
- `/var` is a real persistent subvolume on the atomic host, so the mount
  point, per-workload ACLs and NFS/SFTP export roots survive updates;
- `/etc/fstab` and `/etc/crypttab` are writable and honored, so the mount can
  be declared without changing `/usr`; only packages such as `cryptsetup`,
  `nfs-utils` or `acl` need `rpm-ostree install` (or a container).

The reference shapes now use `/var/mnt/quadronegro`. `/var/mnt` is the persistent
mount convention used by Fedora CoreOS and systemd tooling; `/srv` also works
when it is on the writable `/var` volume. This is a path change only: the
Btrfs filesystem and its contents are unchanged.

## What "access" has to mean

Three layers decide what a workload can do with a path, and they are not
interchangeable:

| layer | question it answers | typical mechanism |
| --- | --- | --- |
| DAC | can this uid read, write, traverse, delete? | owner/group/mode, POSIX ACLs |
| mount view | does this process see the path at all, and is it read-only? | mount namespace, bind mounts, `:ro` |
| MAC | may this domain touch this label, even as root? | SELinux type and MCS categories |

ACLs alone are a weak boundary against a compromised workload because the
owner of a file can change its mode or ACL. Mount views are stronger: a
read-only bind mount cannot be remounted read-write without the capability to
do so. MAC is stronger still, but it needs policy and label discipline.

For the quadronegro data the useful split is therefore:

- **shared media**: root-owned, mounted read-only into workloads;
- **workload state**: owned by the workload uid, writable only by that uid;
- **shared writable projects**: a group or ACL, never a world-writable parent;
- **untrusted work**: a VM with a narrow share or its own disk, not the host
  mount.

## Local segmentation options

| mechanism | granularity | enforced by | usable by a per-user rootless workload? |
| --- | --- | --- | --- |
| POSIX ACLs | per path/inode | DAC | yes, if the parent is traversable |
| systemd bind mounts | per unit and path | mount namespace | yes; the user manager can bind what it can read |
| Btrfs subvolumes | per subvolume and mount | VFS | yes for consuming; mounting usually needs the system manager |
| idmapped mounts | per mount, uid/gid translation | kernel | no in rootless Podman; rootful only |
| user namespaces / subuid | container uid mapping | kernel | yes, but not a host-DAC boundary by itself |
| SELinux MCS | per container category | MAC | yes, with `--security-opt label=level:...` |

The recommended combination for the shared mount is:

1. **ACLs for the data itself**, so the same tree is usable by services,
   containers and remote users without chowning it per workload.
2. **Bind mounts in each systemd unit** (`BindReadOnlyPaths=` for media,
   `BindPaths=` for the workload state), so the read-only view is a kernel
   mount, not a promise.
3. **Btrfs subvolumes** for published read-only media and for quotas, so a
   new media snapshot can be mounted read-only without touching the workload
   directories.
4. **SELinux MCS categories** between containers, and `:ro,z` rather than
   `:Z` for shared binds. `:Z` relabels the whole source for one container and
   breaks every other workload that reads it.

Idmapped mounts are the closest match to "same bytes, different uid per
workload", but they are not available to unprivileged users: Podman documents
its `idmap` mount option as rootful-only, and `mount --map-users` needs the
initial user namespace. A rootful helper or `systemd-nspawn --bind=...:idmap`
can use them; a per-user rootless Podman cannot.

## Worked example: uid 10200, workload u0_a200

Create the identity declaratively with `sysusers.d` (a file under
`/etc/sysusers.d/` persists on an atomic host):

```
u! u0_a200 10200 "workload u0_a200" /var/lib/workloads/u0_a200 /usr/sbin/nologin
g media-ro -
m u0_a200 media-ro
```

A static uid does not get a subordinate range automatically. Add one for
rootless Podman (the numbers are independent of the uid):

```
# /etc/subuid and /etc/subgid
u0_a200:524288:65536
```

A directory layout that keeps the trust boundaries visible:

```
/var/mnt/quadronegro/
  media/                     root:media-ro   2750   # published, read-only
  workloads/u0_a200/         10200:10200     2770   # private, read-write
  shared/<project>/          root:<group>    2770   # explicit group access
```

ACLs for a workload that is not in the media group, plus default ACLs on
directories so new files inherit the rule:

```sh
setfacl -R -m u:10200:rX /var/mnt/quadronegro/media
setfacl -R -d -m u:10200:rX /var/mnt/quadronegro/media
chown -R 10200:10200 /var/mnt/quadronegro/workloads/u0_a200
chmod 2770 /var/mnt/quadronegro/workloads/u0_a200
```

`rX` is read plus traverse on directories, not execute on files. A workload
that must not see a path at all needs a mount view, not an ACL.

A system service gets both views without the workload seeing the rest of the
mount:

```ini
[Unit]
Description=workload u0_a200 example
Requires=var-mnt-quadronegro.mount
After=var-mnt-quadronegro.mount

[Service]
User=10200
Group=10200
PrivateMounts=yes
ProtectSystem=strict
ProtectHome=yes
NoNewPrivileges=yes
StateDirectory=u0_a200
BindReadOnlyPaths=/var/mnt/quadronegro/media:/data/media
BindPaths=/var/mnt/quadronegro/workloads/u0_a200:/data/work
WorkingDirectory=/data/work
ExecStart=/usr/local/bin/workload
```

`BindReadOnlyPaths=` and `BindPaths=` imply a private mount namespace and are
applied per unit. `ProtectSystem=strict` makes the rest of the hierarchy
read-only; `StateDirectory=` creates the writable private state under
`/var/lib/u0_a200`.

For a rootless Quadlet container under the same user, the equivalent view is:

```ini
[Container]
UserNS=keep-id
Volume=/var/mnt/quadronegro/media:/media:ro,z
Volume=/var/mnt/quadronegro/workloads/u0_a200:/work:rw,z
```

`UserNS=keep-id` maps the container user to host uid 10200, so files written
to `/work` stay owned by 10200 instead of a subordinate uid. Use `:U` only on
the private directory; on shared media it recursively chowns the tree. Use
`:z` (shared label) rather than `:Z` (private relabel) for the shared bind.

Enable linger once per workload user so the user manager and its Quadlet units
start at boot:

```sh
loginctl enable-linger u0_a200
```

Test the boundary with the numeric uid before trusting it:

```sh
sudo -u "#10200" test -r /var/mnt/quadronegro/media/example && echo media-readable
sudo -u "#10200" test -w /var/mnt/quadronegro/media/example || echo media-read-only
sudo -u "#10200" touch /var/mnt/quadronegro/workloads/u0_a200/probe && echo state-writable
```

## Rootless Podman per workload

One host user per workload gives each rootless Podman a separate storage
root (`~/.local/share/containers`), a separate user manager, a separate subuid
range and a separate DAC identity. That is the useful part. It does **not**
give the workload a way to escape its own uid, and it does not make the
kernel container boundary a VM boundary.

Rootless Podman can read a system mount only through the permissions the
parent directories grant. It cannot create a system mount or an idmapped mount
itself. The system manager should own the mount, the ACLs and any bind mounts;
the user container consumes them with `:ro` or `:rw`.

For untrusted or exposed work, put the workload in a VM or microVM. Share only
the workload subdirectory through virtiofs or 9p, mount the media share
read-only, and never pass `/dev/mapper` or the raw member devices into the VM.
A VM with its own encrypted disk is a cleaner boundary than any host-side ACL.

## Remote NFS

NFS adds an export-level read-only/read-write decision and its own identity
model. Export leaves, not the whole tree with `crossmnt`, so each path has one
set of options:

```
/var/mnt/quadronegro/media              *(ro,root_squash,sec=krb5p)
/var/mnt/quadronegro/workloads/u0_a200  10.0.0.42(rw,root_squash,sec=krb5p)
```

- `sec=sys` (the default) sends numeric uids and trusts the client. It is
  spoofable by a compromised VM or host; use it only on a network you already
  treat as one security domain.
- `sec=krb5p` authenticates the client and protects the traffic; the server
  maps the Kerberos principal to a local identity. This is the right choice
  when remote workloads have different trust levels.
- `root_squash` stays on. `all_squash,anonuid=10200,anongid=10200` can pin a
  leaf export to one workload identity, at the cost of collapsing every
  client to that identity.
- For a single VM, export only that VM subdirectory to that VM address. For
  several VMs at different trust levels, use separate exports and firewall
  rules, or separate servers.

On Bazzite, `nfs-utils` is usually not in the base image: either
`rpm-ostree install nfs-utils` and reboot, or run the server in a privileged
container. Open the firewall (`nfs`, `mountd`, `rpc-bind`) and check the
SELinux export booleans (`nfs_export_all_ro`, `nfs_export_all_rw`) or label
the export root explicitly.

## Remote SFTP

SFTP is the better fit for per-workload file exchange because the SSH account
is the workload identity and no client-side uid is trusted. One account per
workload, key-only authentication, no shell:

```
Match User u0_a200
  ChrootDirectory /srv/sftp/u0_a200
  ForceCommand internal-sftp -R
  AllowTcpForwarding no
  PermitTunnel no
  X11Forwarding no
  AllowAgentForwarding no
```

`internal-sftp -R` makes the whole session read-only. For a mixed view, chroot
to the workload root and use ACLs: the media bind is read-only and the state
directory is writable. `ChrootDirectory` and every path component above it
must be root-owned and not writable by the user; place the writable directory
below that root.

SFTP does not carry host uids across the network: sshd assumes the account
identity, and the server-side ACLs apply. That is a feature for this model.

## systemd-homed and related pieces

`systemd-homed` is not the right tool for this. It manages per-user home
areas (usually LUKS-encrypted, optionally FUSE-backed) and the user record; it
does not provide per-subtree read-only/read-write views, shared data ACLs,
NFS exports or SFTP chroots. It would add a user-record and PAM layer for
service uids that do not log in.

The useful pieces are smaller:

- `sysusers.d` for the static workload uids and groups;
- `StateDirectory=`, `RuntimeDirectory=` and `LogsDirectory=` for private
  writable state;
- `systemd-cryptsetup@` plus `LoadCredentialEncrypted=` for an encrypted
  private volume per workload, if one is needed;
- `systemd-mountfsd`/`systemd-nsresourced` only if rootless workloads must
  mount their own disk images; they do not segment a shared host directory;
- `systemd-nspawn --bind=...:idmap` for rootful idmapped views, not for
  per-user rootless Podman.

## nsenter, portable services and systemd-portabled

These three are often mentioned together because they are all "systemd-native",
but they sit at different layers.

`nsenter` is an administration tool, not an isolation mechanism. It calls
`setns(2)` to enter the namespaces of an existing process (mount, user, pid,
net, ipc, uts, cgroup, time) and, with `--join-cgroup`, writes the new process
into the target cgroup. That makes it useful for a one-off maintenance command
inside a workload's view and resource limits:

```sh
nsenter --target "$pid" --mount --user --pid --join-cgroup -- /bin/sh
```

It is not a sandbox and it creates no policy. Whoever runs it needs
`CAP_SYS_ADMIN` (or ptrace access) over the target, so it is root-only in
practice. Do not expose it to workload users, do not put it in a workload
image, and do not treat "the workload cannot nsenter" as a security property.
For managed workloads prefer the manager's own entry point, which keeps cgroup
accounting and audit intact: `podman exec`, `machinectl shell`,
`systemd-run --machine`, or a transient unit in the workload slice.

Portable services (`systemd-portabled`, `portablectl`) are a packaging and
deployment model. An image is a directory, btrfs subvolume or raw disk image
containing a `/usr` tree and unit files. `portablectl attach` copies the
matching units to `/etc/systemd/system.attached/` (or the runtime equivalent),
adds a drop-in with `RootDirectory=` or `RootImage=`, and adds a profile
drop-in. The service then runs as a normal systemd unit inside that image, with
cgroup accounting, journal and dependency ordering.

The default profiles are meaningful:

| profile | what it does |
| --- | --- |
| `default` | `DynamicUser=yes`, `PrivateUsers=yes`, `PrivateDevices=yes`, `ProtectSystem=strict`, `ProtectHome=yes`, `SystemCallFilter=@system-service`, `RestrictNamespaces=yes`, D-Bus and logging access |
| `nonetwork` | `default` without network access |
| `strict` | no D-Bus, no network, empty capability set, `TasksMax=4` |
| `trusted` | almost no restrictions; services run with full privileges |

That is a real sandbox for a **trusted** image, and it is entirely
systemd-native: no container runtime, no image registry, no userns management
by the caller. But it is not a multi-tenant boundary:

- the image's unit files are trusted; attaching a malicious image is running
  its code;
- there is no registry, signature policy or digest pinning by default (raw
  images can be pinned with `--pin-protection=yes` and dm-verity, but that is
  integrity, not tenant isolation);
- the profile sets no per-workload SELinux type or MCS category; a portable
  service runs in the normal service domain, so it is usually **less**
  MAC-confined than a Podman container with `container_t` and an MCS pair;
- `DynamicUser=yes` and `PrivateUsers=yes` in the default profile conflict
  with a stable per-workload uid and with bind mounts that assume a fixed
  identity; the `trusted` profile removes the sandbox instead;
- system attach needs root; the user manager variant exists (`systemd-portabled
  --user`, user profiles), but it is still the user's own manager, not a
  cross-user boundary.

`systemd-portabled` itself is just the D-Bus service behind `portablectl`; it
does not add isolation. It is an optional build (`portabled` meson option) and
is not universally shipped; verify with `portablectl --version` and
`systemctl status systemd-portabled` on the host before relying on it.

The practical fit is therefore:

| workload | native fit |
| --- | --- |
| host infrastructure service (backup agent, exporter, sync daemon) | native unit with sandboxing, or a portable service if it must be shipped as one image |
| trusted single-tenant service without a container image | native unit with `User=`, `StateDirectory=`, `ProtectSystem=strict`, `SystemCallFilter=`, `RestrictNamespaces=`, `BindReadOnlyPaths=` |
| trusted per-user workload with a container image | rootless Podman/Quadlet; portable services do not give the per-user userns/storage separation |
| untrusted or exposed workload | VM or microVM; `systemd-vmspawn` is still experimental, so libvirt/KVM or a microVM runtime is the safer choice |
| one-off maintenance inside a workload | `podman exec`, `machinectl shell`, `systemd-run --machine`; `nsenter` only as an explicit root-level debug tool |

For resource isolation, the native building blocks are cgroup v2 plus the
systemd unit settings: `Slice=`, `Delegate=yes`, `CPUWeight=`, `IOWeight=`,
`MemoryMax=`, `TasksMax=`, and `DeviceAllow=`. Rootless Podman needs the user
slice delegated so it can create per-container scopes; without delegation the
limits land on the whole user manager. Use `systemd-cgtop`/`systemd-cgls` for
accounting and `systemd-analyze security` for a sandbox score. `nsenter
--join-cgroup` is a convenient way to run a maintenance command under the same
limits, but it is not a substitute for the unit's own policy.

## Subuid ranges are plumbing, not identity

A subuid/subgid range is an implementation detail of the user namespace. The
host user (for example 10200) is the stable DAC identity; the range
(`524288:65536`) is what container-internal uids map to. Using the range as
the data identity is possible, but fragile:

- files on disk are owned by numeric uids with no passwd entry, so `ls`,
  backups, quotas, audit and NFS idmapping all need special handling;
- the range can change when `/etc/subuid` changes or when `--userns=auto`
  allocates a different block;
- `chown` requires `podman unshare`, and host tools cannot reason about the
  owner;
- several rootless containers under one host user share the same range by
  default, so it is not a per-workload boundary;
- POSIX ACLs name a single uid/gid, not a range; granting access to "the
  workload" means naming one mapped id or creating a group and mapping gid 0
  to it.

The reliable pattern is a real host uid per workload plus `--userns=keep-id`
(Quadlet `UserNS=keep-id`) so the container user writes as that uid. The
subuid range stays for container root and system users. ACLs then grant
`deck`, backup or a shared group access without touching ownership. ACLs do
not replace the uid mapping; they complement it.

If a workload must run as container root, map container root to the host uid
explicitly (`--uidmap 0:10200:1`) or accept subuid-owned files. The first
weakens in-container isolation; the second is the unreliable path for shared
data.

## NFS as a shortcut

NFS can remove some ownership work, but not the identity work:

- a rootless container cannot mount NFS itself (the NFS client is not
  user-namespace mountable); the host mounts it and the container uses a bind
  or a rootful volume;
- `all_squash,anonuid=10200,anongid=10200` makes all client writes appear as
  10200 on the server, so no subuid chown is needed for that export, but every
  client shares the same identity;
- per-workload exports with different `anonuid`, or `sec=krb5p` with
  per-workload principals, restore separation at the cost of a KDC and export
  management;
- `sec=sys` trusts client uids and is spoofable, so it is not a boundary for
  untrusted workloads;
- SELinux sees an NFS mount as `nfs_t`; `:Z` cannot relabel NFS. Use a
  `context=` mount option or `--security-opt label=disable`, and understand
  that the latter gives up the SELinux layer for that container;
- NFS does not stop a compromised workload from using the access the export
  grants. It is a sharing protocol, not a sandbox.

NFS is reasonable for cross-host or VM sharing and for avoiding bind relabels.
It is not a way to skip per-workload identities, and it is a poor default for
untrusted workloads on the same host.

## Custom SELinux types and privilege escalation

SELinux type enforcement is the layer that still applies after a workload
gains root inside its container or user namespace. A process in
`workload_u0_a200_t` remains in that domain even as uid 0; it can only touch
types the policy allows. MCS categories (`s0:c200,c201`) already separate
containers from each other and from `user_home_t`. Custom types go further:

- `workload_media_ro_t`: readable by every workload domain, writable by none;
- `workload_state_u0_a200_t`: managed only by `workload_u0_a200_t`;
- `workload_shared_<project>_t`: read/write only for the declared domains.

This increases security against a workload that escalates to root *inside its
domain*: DAC is bypassed by root, SELinux is not. It does not protect
against:

- a kernel or SELinux bypass exploit (SELinux lives in the kernel);
- a transition to `unconfined_t` or a policy-loading domain, if the workload
  can execute it; drop `CAP_MAC_ADMIN`, `CAP_SYS_ADMIN` and `CAP_SYS_MODULE`,
  and do not allow `setexeccon` or `semodule`;
- a host root process that is already unconfined.

For rootless Podman, the runtime may be allowed to set only `container_t`
plus MCS categories; arbitrary `label=type:` transitions need policy support
and should be tested. Rootful Podman already uses `container_t` plus MCS
categories. Libvirt uses the same idea with `svirt_t` and per-VM MCS
categories, and labels each disk image `svirt_image_t:s0:cX,cY`; the VM
process cannot read another VM image even if DAC would allow it. That is the
closest thing to the Android per-app model on a Linux host, and it is the
right default for VMs.

On an immutable host, custom policy is a `semodule -i`/`rpm-ostree` layer,
and file labels are set with `semanage fcontext` plus `restorecon`. Keep the
policy small and test it on a scratch tree before labeling the live data.

## Migration order

1. Mount the filesystem at `/var/mnt/quadronegro`, verify with `findmnt`, and
   confirm the mount unit is the only owner (no udisks mount of the same
   filesystem).
2. Create the layout, the workload users and the ACLs while uid 1000 still has
   access; test with `sudo -u "#10200"`.
3. Move shared trees to a root-owned group and keep an explicit ACL for
   `deck`, so the admin user is not the owner of shared data.
4. Convert one trusted workload to its per-user rootless Podman with
   `keep-id` and `:ro`/`:rw` volumes; verify file ownership on both sides.
5. Add NFS or SFTP for one leaf path and test from a separate VM or host;
   keep `sec=sys` off any network that is not already trusted.
6. Only then retire rootful Docker and the shared-uid rootless Podman.

## Open decisions

- whether NFS is needed at all for local microVMs, or whether virtiofs or a
  per-VM disk is the better default;
- whether the fourth LUKS candidate (`545db2db-...`) is a live member;
- whether shared media is published as a read-only Btrfs snapshot or merely
  mounted read-only, and how updates swap the snapshot;
- whether SELinux MCS categories are enough between containers, or a custom
  type per workload class is worth the policy maintenance;
- whether the per-workload private state is a directory, a LUKS volume, or a
  systemd-homed-style encrypted home (the last is not recommended for
  non-login service uids).

## Non-goals

- No claim that DAC or ACLs stop a compromised kernel or a root process.
- No claim that rootless Podman is a VM boundary.
- No automatic chown or relabel of the live data.
- No NFS export or SFTP account installed by this note.