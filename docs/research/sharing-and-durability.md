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
- **`-single` means encryption only**: one encrypted copy, no parity, no
  replication. It exists for data that already has redundancy elsewhere, where
  adding more would spend storage and CPU for nothing.
- **`-fec` means PAR2-style parity over the raw ciphertext**, about 10 %
  overhead for a 5 % recovery target. It is bitrot repair, not erasure coding:
  it repairs damage inside a surviving object and cannot resurrect a deleted
  one. Over ciphertext, a blind restorer can verify a repair without the key.

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
policy: { copies: 2, parity: "par2:10%", ack: "n-volumes", created: ... }
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
| `.quadronegro-fec` | each copy carries a **PAR2/PAR3 parity set over its ciphertext**, about 10 % overhead with a 5 % recovery target; the acknowledgement waits for the parity to be durable | a parity configuration MUST exist for the folder's tier |
| `.quadronegro-single` | **encryption only**: one encrypted copy, no parity, no replication, no background copy; acknowledged after the local write and manifest are durable | exclusive with `-c<N>` and `-fec` in the same directory, including `-c1` |

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
  without a parity configuration) is accepted if it is merely unreachable
  *now*, and writes fail until it becomes reachable. The creation SHOULD warn;
  the write-time failure is the authority.
- Markers are created and deleted atomically (create-then-rename), and the
  daemon MUST `fsync` the marker's directory before the new default applies.

### Why `-single` exists

Some folders hold data that is **already** redundant, hashed or parity
protected: a restic repository, a `par2` archive, a git bundle, an output
already replicated by another tool. Copying or parity-encoding that again
spends storage and CPU to protect bytes that are already protected, and it
makes the outer layer fight the inner one.

So `-single` says: apply the encryption layer, store one copy, and stop. The
engine still records the content hash, so bitrot is **detected** and reported —
it is simply not repaired locally, because the inner format already knows how
to do that. It also suppresses the background upload and the lazy parity that a
default policy would otherwise schedule; that was the mistake in the earlier
draft, which kept them "best effort".

`-single` is not a silent fallback. A `-c<N>` folder whose domains are missing
fails its writes; the operator writes `-single` to make the downgrade explicit,
and removes it when the domains return.

### Inheritance and precedence

- A marker applies to its directory and is inherited by subdirectories that
  have no marker of their own: **nearest ancestor wins**.
- `-c<N>` and `-fec` combine: N copies, each carrying parity.
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
3. with `-fec`, each copy's parity set is computed over that copy's final
   ciphertext, written, and durable; the manifest records the set id and the
   block hashes;
4. the manifest entry — policy, root hash, per-copy locators, parity reference
   — is written atomically (rename or conditional PUT) and durable.

For `-single`, only steps 1 and 4 run: the local object and the manifest. No
copy, no parity, no background job.

Anything less returns `EIO`, leaves the previous manifest version in place, and
leaves the orphaned staging objects to the collector. The order is not
negotiable: data, then parity, then the manifest that names them.

### FEC: parity over the ciphertext

`-fec` is not erasure coding for a lost volume. It is **bitrot repair inside a
surviving object**, and its shape follows from that:

- **Order.** Encrypt → object → parity over the ciphertext → manifest. Parity
  over plaintext would leak linear combinations and would need the key to
  check.
- **Blind verification.** A PAR2 set carries the file size, per-block hashes
  and the set id, so `par2 verify` decides whether an object is intact and
  whether a repair produced the right bytes — without the key and without
  knowing what the bytes mean. That is the property the request asked for: a
  blind restorer can state "this object is correct" and hand it to the key
  holder.
- **Overhead and target.** About 10 % of the object as recovery blocks, with a
  design target of 5 % of blocks recoverable. The gap is margin: parity itself
  rots, and a repair consumes blocks. More parity than that is the wrong
  purchase — an object missing more than a few percent of its blocks needs a
  copy.
- **Granularity.** Block size 64–256 KiB keeps one bad byte from condemning
  much data; PAR2's per-file block limit (32768) sets the floor for very large
  objects (1 GiB at 256 KiB is 4096 blocks; 1 TiB needs 32 MiB blocks).
- **What it cannot do.** It cannot reconstruct a deleted or wholly missing
  object: that needs 100 % parity, which costs more than a second copy. It
  cannot repair an object that lost more blocks than the parity set carries; it
  reports the object as unrecoverable instead.
- **Scope.** Per object, next to the object, in the backing store. The parity
  files are not part of the plaintext view; a synthetic xattr reports their
  state. Per-folder parity sets are possible for sealed cold archives but break
  per-file acknowledgement, so they are a separate, explicit mode.
- **Metadata.** The object id is opaque; the PAR2 packets carry that id, the
  size and the hashes, not the plaintext name. Do not encrypt the parity set —
  that would defeat blind verification — and do not put plaintext names in it.
- **Tooling.** `par2cmdline-turbo` is the mature, multithreaded
  implementation. PAR3 is a newer specification with better hashing but thinner
  tooling; the contract names the properties, not the binary.

### Copies, shards and domains

A **domain** is an independently failing unit, declared in configuration: a
physical device (not a partition), a remote provider or bucket, or a host. Two
copies on one device are one domain. Two USB disks behind one hub are one
domain if the hub is in the failure model — which the pool's own audit says it
should be.

- `-c<N>` requires N distinct domains per object; placement MUST NOT put two
  copies on one domain.
- `-fec` does not spread a copy across domains: the parity set lives with its
  object, and the *copies* are what cross domains. That is the whole difference
  from erasure coding, and it is why a lost domain costs the object and its
  parity together.
- Storage overhead is N × 1.10 for `-c<N> -fec`, N × 1.00 for `-c<N>`, and
  1.00 for `-single`. Bound N and the parity ratio with a per-folder and
  per-workload quota, and reject markers that exceed it.

### Failure semantics

| situation | behaviour |
| --- | --- |
| one domain offline | `-c<N>` `fsync` fails `EIO` after `commit_timeout`; the old version stays committed; reads continue from surviving copies |
| fewer than N domains exist | writes fail `EIO`/`ENOSPC`; the marker stays, so the guarantee is restored when capacity returns |
| `commit_timeout` expires | `EIO`; the commit stays pending and retryable; a hung USB or SMR device cannot stall `fsync` forever |
| crash mid-commit | the manifest was not published; the previous version is intact; staging objects are collected |
| parity write fails | the whole `fsync` fails; a partial parity set is never acknowledged |
| bitrot inside the parity budget | the block is detected on read or scrub, repaired from parity, and the repair is verified against the block hashes |
| bitrot beyond the parity budget | reported as unrecoverable; only another copy can restore the object |
| object deleted or entirely missing | parity cannot help; only a copy restores it |
| copy later diverges | the manifest hash decides; the failing copy is ignored, repaired, and reported |
| marker invalid or contradictory | `EIO` until corrected; never a silent downgrade |

### Verification and observability

- A **read-only synthetic xattr** on each object reports its recorded policy,
  copy states, parity state, last verification time and last repair. `setxattr`
  on it returns `EPERM`. A directory's xattr reports the effective inherited
  policy.
- A `verify` job walks markers and manifests and reports **drift**: objects
  whose actual copies or parity are below their recorded policy, objects whose
  policy no longer matches the folder default, pending `-single` completions
  older than a threshold, and objects whose parity set is itself damaged.
- `par2 verify` is the blind check: it needs the object and the parity set, not
  the key, and its output is quotable in an incident report.
- Metrics: `fsync` latency by policy, pending commits, failed commits by
  reason, bytes written per domain, repaired blocks, unrecoverable objects.

### Security of the markers themselves

- A workload can only change the default for folders it can write. It can
  choose `-single` (and so lower its own guarantee) only if its declaration
  allows `single_ack`; otherwise the marker create fails `EPERM`. It can never
  weaken another workload's objects, because policy is recorded per object.
- A workload that sets a high N or a large parity ratio spends storage, so N,
  the ratio and the overhead product are bounded per workload by quota.
- Marker creation, deletion, parity set creation and every rejected invalid
  state are audited with the workload identity and the effective policy.
- The marker path is resolved with the same `openat2` rules as any other
  request; a symlinked or `..`-relative marker is rejected.
- Markers are metadata, never keys. A folder's key scope is configuration, not
  a file a workload can edit.
- Parity over ciphertext is safe to store next to the ciphertext: it is a
  linear combination of pseudorandom blocks. Do not store a plaintext parity
  set, and do not let the object id leak the name.

### Examples

| folder | markers | what an `fsync` means |
| --- | --- | --- |
| `media/films` | `.quadronegro-c2` | durable on two declared domains; no parity |
| `media/films/archive` | `.quadronegro-c2` + `.quadronegro-fec` | two copies, each with a 10 % parity set, all durable |
| `work/scratch` | `.quadronegro-single` | one encrypted local copy and manifest; no copy, no parity, no upload |
| `restic-repo` | `.quadronegro-single` | already content-addressed and self-checking; encrypt once, store once |
| `work/scratch/important` | `.quadronegro-c3` | overrides the inherited `-single`: three copies before ack |

### Tests the contract needs

- crash injection between each pair of commit steps, asserting the old version
  survives and no partial copy or parity set is acknowledged;
- one domain removed during `fsync`, asserting `EIO` at the timeout and an
  intact previous version;
- `-c<N>` with N greater than the domain count, asserting failure and the error
  text;
- inject a bad byte inside the parity budget, asserting detection, repair and
  post-repair verification; inject damage beyond the budget, asserting the
  object is reported unrecoverable rather than silently served;
- delete an object, asserting parity does not pretend to restore it and the
  report says a copy is required;
- verify and repair with no key available, asserting the blind path works and
  the result is bit-identical;
- damage the parity set itself, asserting the report distinguishes "object
  damaged" from "parity damaged";
- marker edited while a writer is open, asserting the writer keeps its recorded
  policy;
- `rename` across folders with different markers, asserting the recorded policy
  does not change;
- invalid marker combination, asserting `EINVAL` on create and `EIO` on write
  after a hand edit;
- `commit_timeout` with a stalled backend, asserting `fsync` returns rather
  than hangs;
- throughput with and without the writeback cache, and with 128 KiB versus
  1 MiB requests, recorded next to the design;
- parity cost measured for a 1 GiB object at 256 KiB blocks: creation time,
  verify time, repair time.

## Open questions

1. PAR2 or PAR3? PAR2 is the mature choice; PAR3's better hashing is only worth
   it if a maintained implementation exists for the target platforms.
2. Is the parity ratio per folder (5 %, 10 %, 20 %) or fixed at 10 %? The
   request says ~10 % overhead for ~5 % recovery, which suggests a fixed pair
   with no per-folder tuning; a per-folder ratio is more flexible and more to
   get wrong.
3. Per-object parity sets are the default; is a per-folder set worth building
   for sealed cold archives, given it breaks per-file acknowledgement?
4. Does `-single` still allow a workload's *own* upload (for example a
   restic push), or does it forbid the engine from touching the data at all?
   The clarification says no engine copies; the workload's own tools are
   outside the engine and unaffected.
5. Is `-c1` allowed as distinct from `-single`, or is it rejected as a
   confusing synonym? The difference is real — `-c1` still makes the engine
   place and manage one copy, `-single` does not — but the value is low.
6. Should parity sets be visible in the plaintext view (a `.par2` file the
   workload can see) or only in the backing store with a status xattr? Hiding
   them is cleaner and prevents a workload from damaging its own repair data.
7. What is the measured throughput floor below which a workload is moved to
   the plain-LUKS or fscrypt rung, and who decides?

## Status

Draft design note, revised for the `-single` and PAR2 corrections. The sharing
comparison is grounded in the virtiofsd, libkrun and FUSE material already cited
in the [VM note](microvm-composition.md); the marker contract is new. No daemon
was built, no marker was exercised, and no host was queried.
