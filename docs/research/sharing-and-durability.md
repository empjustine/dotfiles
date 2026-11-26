---
id: research-sharing-and-durability
type: architecture-design
status: draft
title: "File-level sharing and per-folder durability markers"
parent: index
references: [index, research-storage-overlay, research-microvm-composition, research-multi-uid-access, research-files-volumes, decision-log]
---

# File-level sharing and per-folder durability markers

Two questions from the storage design, answered together because the same
component answers both: what is the least vulnerable way to share files at file
granularity with acceptable performance and per-file confidentiality, and how
should the `.quadronegro-*` marker files change the persistence guarantee of
the folder that contains them?

The short answers:

- **A small FUSE daemon, one mount per workload, is the least vulnerable shape
  that still gives per-file encryption.** Network filesystems (NFS, SMB, 9p)
  are excluded on the same host; `virtio-fs` is for VMs and only over a plain
  directory; a plain per-workload LUKS volume is the fast path for trusted
  bulk data with no per-file keys.
- **Markers are defaults for new objects, recorded per object at creation, and
  enforced at the write barrier, not retroactively.** They cannot work without
  a policy point in the write path, and on POSIX that point is the FUSE daemon.

Normative words (**MUST**, **SHOULD**, **MAY**) are used only in the marker
contract, because that section is a specification rather than a discussion.

## Part 1 — the sharing interface

### What is being compared

| mechanism | attacker-reachable code | privileges | large-file throughput | per-file keys | plain ciphertext files |
| --- | --- | --- | --- | --- | --- |
| bind mount of a plain directory on LUKS | kernel only | none extra | native | no | no (LUKS image) |
| fscrypt on ext4/f2fs | kernel only | keyring | near-native | per directory | no (inside the filesystem) |
| FUSE daemon, ours or gocryptfs-shaped | one userspace FS | unprivileged daemon | good for large I/O, weak for metadata | yes | yes |
| virtio-fs (for VMs only) | virtiofsd (root) + guest driver | root/fake root | good, DAX for large files | only if the guest holds the key | yes, if the export is ciphertext |
| NFS server | kernel `nfsd` or a userspace server | root, Kerberos for `sec=krb5p` | good | no | no |
| SMB/Samba | `smbd` | root or per-share uid | good | no | no |
| 9p | guest/host driver | root | poor | no | no |
| object API with a client in the guest | the client | unprivileged | network-bound | yes | yes |

Two rows deserve their verdict stated plainly. **NFS and SMB are network
protocols**: they bring a large parser surface, an identity model (`sec=sys`
trusts numeric uids; `sec=krb5p` needs a KDC), and a server that can read every
exported plaintext. On one host they buy nothing that a bind mount does not,
and they cost the most attack surface per byte. **9p** has the weakest security
story of the three and is not worth considering for untrusted guests.

### The recommendation

**One small FUSE daemon per host, one mount per workload, mounted in that
workload's mount namespace.** It is simultaneously the encryption point and the
durability-policy point, which is the whole reason to accept a userspace
filesystem in the path.

The design constraints that keep it least vulnerable:

- **No network listener.** The only socket is outbound to the object backends.
  There is no RPC surface to authenticate, no port to expose, no protocol to
  version.
- **Unprivileged.** A dedicated uid, no root, no `CAP_SYS_ADMIN`. The mount is
  created by the host service and bind-mounted into the workload's namespace;
  rootless Podman cannot create it itself, and does not need to.
- **One mount per workload, and the mount is the capability.** The daemon
  selects the key from the mount instance, not from the uid in the request. A
  uid inside a container is not a trustworthy identity; a mount namespace is.
  This also makes sharing explicit: a folder shared by two workloads gets one
  folder key wrapped for each, and no other key reaches either mount.
- **No `allow_other`.** It requires `user_allow_other`, it makes one mount
  reachable by every uid on the host, and it turns every permission decision
  into daemon logic. Per-workload mounts avoid it entirely.
- **`default_permissions` on**, so the kernel enforces mode bits from the
  attributes the daemon reports, and the daemon's own checks are a second gate
  rather than the only one.
- **Path resolution with `openat2(RESOLVE_BENEATH | RESOLVE_NO_SYMLINKS |
  RESOLVE_NO_MAGICLINKS)`**, so a symlink or a `..` in a request cannot leave
  the workload's subtree even if a bug lets the request through.
- **Small and boring.** Rust, `fuser`/`polyfuse`, no plugins, no scripting, no
  configuration language in the data path. Fuzz the request handler; run
  `cargo audit` in the gate; keep the op set to what the rung needs.
- **Systemd sandboxing** on the daemon unit: `NoNewPrivileges=yes`,
  `ProtectSystem=strict`, `ProtectHome=yes`, `PrivateNetwork=yes` except the
  backend, `SystemCallFilter=@system-service`, `MemoryMax=`, `TasksMax=`,
  `LimitNOFILE=`.

### Performance, honestly

A FUSE daemon adds a context switch and a copy per request. The levers are
known and worth setting deliberately:

- negotiate the largest request size the kernel allows (up to 1 MiB when the
  daemon advertises more pages; 128 KiB is the common default), and enable
  `FUSE_BIG_WRITES`, `FUSE_ASYNC_READ`, `FUSE_PARALLEL_DIROPS`;
- enable the writeback cache so the kernel coalesces small writes into large
  ones; `fsync` still flushes them, so the policy barrier is unaffected;
- batch the commit protocol: one manifest update per `fsync`, not per `write`;
- encrypt per fixed-size extent (128 KiB–1 MiB) with an independent AEAD
  nonce, so random writes do not re-encrypt the file;
- use a fast AEAD (AES-GCM with AES-NI or XChaCha20-Poly1305) and `splice` for
  large reads;
- cache dentries and attributes aggressively (`default_permissions` makes this
  safe), and accept that metadata-heavy work (package installs, `git status`
  on a cold cache) is where FUSE loses, not in bulk I/O.

Expect large sequential I/O to land within a small factor of the backing store
and small-file metadata operations to be several times slower than a kernel
filesystem. Measure on this hardware before promising numbers; the design
should record the measured figure next to the choice.

### The performance escape hatch, and why it is not the default

Kernel `fscrypt` on ext4/f2fs gives per-directory keys with no userspace
filesystem in the path, and FUSE passthrough can hand a backing file to the
kernel so reads and writes bypass the daemon. Combined, they would give
near-native speed with kernel-enforced encryption and a daemon that only gates
metadata and the `fsync` barrier — attractive, but:

- fscrypt is per **directory**, not per file, and its names and contents live
  inside a filesystem image, so the "plain ciphertext files a restorer can
  walk" property is lost;
- fscrypt does not exist on btrfs, and the pool is moving to one filesystem per
  device anyway;
- passthrough plus an encrypted backing file needs kernel support that is still
  recent, and whether the `fsync` barrier still reaches the daemon in that mode
  needs verification before it can carry the marker contract.

Keep it as a measured option for a bulk-media rung, not as the default.

### What this means for VMs

`virtio-fs` exports a **plain directory**, not the FUSE view: stacking FUSE on
FUSE costs the file-handle fast path, DAX and a second round of xattr mapping,
as the [VM note](microvm-composition.md) records. The consequence for this
design is blunt: **a plain-directory export bypasses the policy point**, so
markers are not enforced for writes that enter through `virtio-fs`. A VM that
needs marker semantics has three options: run the object client inside the
guest (best: markers become an API contract, and only ciphertext crosses the
boundary), accept a stacked FUSE export, or accept that the VM's writes carry
no per-folder guarantee until the host's sync job processes them.

## Part 2 — the marker contract

### The model

A marker is a **default for objects created after it**, not a property of the
directory that retroactively applies. Every object records its policy at
creation in its manifest entry:

```
policy: { copies: 2, fec: false, ack: "n-volumes", created: 2026-11-26T... }
```

Consequences, all deliberate:

- changing or deleting a marker never weakens an object that already exists;
- renaming an object into a folder with a different marker does not change its
  recorded policy;
- a restore recreates the object with its recorded policy, and recreates the
  marker in the view for the operator's benefit;
- re-applying a folder's current policy to existing objects is an explicit
  migration command, never a side effect of a marker edit.

### Grammar and validity

| marker | meaning | constraint |
| --- | --- | --- |
| `.quadronegro-c<N>` | exactly **N** copies, acknowledged only after all N are durable on N distinct domains | N is a decimal integer, 1–9, not exceeding the configured domain count and the workload's quota |
| `.quadronegro-fec` | each copy is stored as **k+m** shards; the acknowledgement waits for every shard, parity included, to be durable | a k+m scheme MUST be configured for the folder's tier |
| `.quadronegro-single` | acknowledge after the **local** durable write and manifest; copies and FEC continue in the background, best effort | exclusive with `-c<N>` and `-fec` in the same directory |

Rules:

- The three names are exact and lowercase. A marker is a zero-length regular
  file. Writing content to it MUST fail with `EINVAL`; `chmod` and `chown` on
  it are ignored.
- An unknown `.quadronegro-*` name is ignored with a warning in the audit log;
  a `strict_markers` config makes it a write error instead.
- `-single` alongside `-c<N>` or `-fec` in the same directory is invalid:
  creating such a marker MUST fail with `EINVAL`, and the previous policy
  stands. A hand-edited or restored invalid state MUST fail closed: writes in
  that directory return `EIO` until it is corrected, and the audit log names
  the file.
- A marker that names an impossible guarantee (N larger than the domains, FEC
  without a scheme) is accepted if it is merely unreachable *now*, and writes
  fail until it becomes reachable. The creation SHOULD warn; the write-time
  failure is the authority.
- Markers are created and deleted atomically (create-then-rename), and the
  daemon MUST `fsync` the marker's directory before the new default applies.

### Inheritance and precedence

- A marker applies to its directory and is inherited by subdirectories that
  have no marker of their own: **nearest ancestor wins**.
- `-c<N>` and `-fec` combine: N copies, each FEC-encoded.
- `-single` replaces an inherited `-c<N>` or `-fec` entirely for new objects in
  its subtree; it never combines with them.
- The root of a managed tree SHOULD carry an explicit marker so the default is
  visible rather than implied.

### What "confirmed" means

The barrier set is where the guarantee is observable. The default:

| operation | waits for the policy? |
| --- | --- |
| `write`, `pwrite`, `writev` | no — buffered, as on any filesystem |
| `O_SYNC` / `O_DSYNC` write | yes, per write |
| `fsync`, `fdatasync` | yes — the primary barrier |
| `syncfs` | yes, for every dirty object in the mount |
| `msync` + `fsync` | yes; `msync` alone and `munmap` are not barriers |
| `close` | no by default; a `close_barrier` config MAY make it one |
| `rename` + `fsync(dir)` | the directory barrier waits for the namespace update and for pending commits of objects whose names changed in that directory |

The canonical atomic-replace sequence is therefore: write → `fsync(file)` →
`rename` → `fsync(dir)`. Document it, and make the test suite assert it.

### The commit protocol

For an object under `-c<N>`, `fsync` returns only after all of:

1. every buffered extent is written to the staging object and `fsync`ed;
2. N distinct domains each hold a durable copy — a local `fsync` for a local
   backend, a completed and verified PUT for an object store, an object-locked
   PUT where immutability is configured;
3. with `-fec`, every copy's k data shards and m parity shards are durable, and
   the parity was computed from the final ciphertext;
4. the manifest entry — policy, root hash, per-shard hashes, copy locators — is
   written atomically (rename or conditional PUT) and durable.

Anything less returns `EIO`, leaves the previous manifest version in place, and
leaves the orphaned staging objects to the collector. The order is not
negotiable: data, then parity, then the manifest that names them.

FEC is computed per fixed-size extent (recommended 4–8 MiB), not over the whole
file, so an append re-encodes only the extents it touched. `-fec` makes the
encode synchronous and part of the latency; folders without it get FEC lazily
at tiering, where the cost does not sit in a write.

### Copies, shards and domains

A **domain** is an independently failing unit, declared in configuration: a
physical device (not a partition), a remote provider or bucket, or a host. Two
copies on one device are one domain. Two USB disks behind one hub are one
domain if the hub is in the failure model — which the pool's own audit says it
should be.

- `-c<N>` requires N distinct domains per object; placement MUST NOT put two
  copies on one domain.
- FEC shards of one copy MUST also be on distinct domains where the scheme
  allows it, because a lost domain otherwise takes both a data and a parity
  shard.
- Storage overhead is N copies × (k+m)/k shards. A folder with `-c3 -fec` at
  4+1 therefore costs 3.75× the plaintext. Bound the product with a per-folder
  and per-workload quota, and reject markers that exceed it.

### `-single`, precisely

`-single` is the operator's explicit statement that redundancy exists
elsewhere. `fsync` returns after the local copy and the manifest are durable;
the engine still schedules copies and FEC in the background, best effort, and
records their state. It is also the natural way to keep writing while a domain
is missing: create `-single`, accept the weaker ack, remove it when the domain
returns. It is not a silent fallback — a `-c<N>` folder whose domains are
missing fails its writes, and the operator must choose the downgrade.

### Failure semantics

| situation | behaviour |
| --- | --- |
| one domain offline | `-c<N>` `fsync` fails `EIO` after `commit_timeout`; the old version stays committed; reads continue from surviving copies |
| fewer than N domains exist | writes fail `EIO`/`ENOSPC`; the marker stays, so the guarantee is restored when capacity returns |
| `commit_timeout` expires | `EIO`; the commit stays pending and retryable; a hung USB or SMR device cannot stall `fsync` forever |
| crash mid-commit | the manifest was not published; the previous version is intact; staging objects are collected |
| parity write fails | the whole `fsync` fails; a partial FEC set is never acknowledged |
| copy later diverges | the manifest hash decides; the failing copy is ignored, repaired, and reported |
| marker invalid or contradictory | `EIO` until corrected; never a silent downgrade |

### Verification and observability

- A **read-only synthetic xattr** on each object reports its recorded policy,
  copy states, FEC state and last verification time. `setxattr` on it returns
  `EPERM`. A directory's xattr reports the effective inherited policy.
- A `verify` job walks markers and manifests and reports **drift**: objects
  whose actual copies or parity are below their recorded policy, objects whose
  policy no longer matches the folder default, and pending `-single`
  completions older than a threshold.
- Metrics: `fsync` latency by policy, pending commits, failed commits by
  reason, bytes written per domain, drift count.

### Security of the markers themselves

- A workload can only change the default for folders it can write. It can
  lower its own guarantee (`-single`) only if its declaration allows
  `single_ack`; otherwise the marker create fails `EPERM`. It can never weaken
  another workload's objects, because policy is recorded per object.
- A workload that sets a high N or `-fec` spends storage, so N, the FEC
  scheme and the overhead product are bounded per workload by quota.
- Marker creation, deletion and every rejected invalid state are audited with
  the workload identity and the effective policy.
- The marker path is resolved with the same `openat2` rules as any other
  request; a symlinked or `..`-relative marker is rejected.
- Markers are metadata, never keys. A folder's key scope is configuration, not
  a file a workload can edit.

### Examples

| folder | markers | what an `fsync` means |
| --- | --- | --- |
| `media/films` | `.quadronegro-c2` | durable on two declared domains; the second may be the cloud copy |
| `media/films/archive` | `.quadronegro-c2` + `.quadronegro-fec` | two copies, each 8+1, all shards durable, manifest durable |
| `work/scratch` | `.quadronegro-single` | the local copy and manifest are durable; upload and FEC are queued |
| `work/scratch/important` | `.quadronegro-c3` | overrides the inherited `-single`: three copies before ack |

### Tests the contract needs

- crash injection between each pair of commit steps, asserting the old version
  survives and no partial copy is acknowledged;
- one domain removed during `fsync`, asserting `EIO` at the timeout and an
  intact previous version;
- `-c<N>` with N greater than the domain count, asserting failure and the error
  text;
- `-fec` with one parity shard corrupted after the fact, asserting the verifier
  names the shard and the repair succeeds from k data shards;
- marker edited while a writer is open, asserting the writer keeps its recorded
  policy;
- `rename` across folders with different markers, asserting the recorded policy
  does not change;
- invalid marker combination, asserting `EINVAL` on create and `EIO` on write
  after a hand edit;
- `commit_timeout` with a stalled backend, asserting `fsync` returns rather
  than hangs;
- throughput with and without the writeback cache, and with 128 KiB versus
  1 MiB requests, recorded next to the design.

## Open questions

1. Do `-c<N>` and `-fec` mean N **copies** (this document) or N **domains over
   which one FEC set is spread**? The marker name suggests copies; the cost of
   `-c3 -fec` is high enough that the answer must be explicit.
2. Is `close` a barrier? The default is no; a `close_barrier` global setting is
   the escape hatch for applications that never call `fsync`.
3. Is a per-folder key scope enough, or does a single file ever need its own
   key? Per-file keys are already the object format; per-file *scopes* are not.
4. Should markers be settable through the object API (a prefix policy) and the
   git rung, or only through the `files` view? One policy model across rungs is
   cleaner but needs a representation in each.
5. Does the FUSE daemon serve one mount per workload process, or one per
   workload identity with several bind mounts? The former is simpler to reason
   about and costs a daemon thread per mount.
6. What is the measured throughput floor below which a workload is moved to
   the plain-LUKS or fscrypt rung, and who decides?

## Status

Draft design note. The sharing comparison is grounded in the virtiofsd, libkrun
and FUSE material already cited in the [VM note](microvm-composition.md); the
marker contract is new. No daemon was built, no marker was exercised, and no
host was queried.
