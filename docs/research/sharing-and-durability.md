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

### What the encryption layer is

The design does **not** use gocryptfs as its encryption layer. It uses a FUSE
daemon that borrows gocryptfs's *block format* and replaces its *key model*:

| | stock gocryptfs | this design |
| --- | --- | --- |
| key hierarchy | one master key per volume, wrapped by a password (scrypt) or FIDO2 in `gocryptfs.conf`, or supplied through `-extpass` / `-masterkey` | root key (offline) → per-workload KEK (wrapped) → per-object DEK (random, wrapped by the KEK, stored in the header or manifest) |
| residency | the master key lives for the mount's lifetime; `-idle` unmounts and drops it | the KEK lives for the mount's lifetime, the DEK for the file's open lifetime; both are zeroed on release |
| rotation | `-passwd` rewraps the master key; the data is not re-encrypted | rewrap the DEKs under a new KEK; the data is not re-encrypted |
| revocation | unmount; the volume key is unchanged | drop the workload's KEK wrap — a crypto-shred of that workload |
| format | 18-byte header (version, file id) plus independently encrypted 4 KiB blocks | the same block shape, plus a wrapped-DEK header field and a manifest entry |
| `fsync` | passes through to the backing filesystem | intercepted: copies, parity, manifest, markers |

**Key lifetimes**, concretely — this is what "short-lived" means, and it is
about residency, not about fetching a key per I/O:

| key | held where | lifetime | released by |
| --- | --- | --- | --- |
| root key | offline (paper, HSM, sealed credential) | forever | never in RAM |
| workload KEK | the key daemon / mount process, `mlock`ed | the mount | unmount, idle timeout, TTL expiry, revocation |
| object DEK | the daemon, per open file | the open | `close`, unmount, crash |

A per-file network fetch from the injector is possible and is not the default:
the DEK is unwrapped locally from the KEK with AES-KW, which costs
microseconds, while a fetch costs a round trip and would put the injector on
the I/O path. Rotation is a rewrap, not a re-encryption, so it can happen
lazily on the next open.

### What gocryptfs can and cannot be

Short-lived keys do **not** make the design incompatible with gocryptfs. Its
`-extpass` hook is exactly the injector path (run a command, take the password
from its stdout), `-idle` unmounts after an idle period and drops the key, and
one mount per workload is one master key per workload. That is a coherent
mount-scoped key design, and it is the pilot.

What *is* incompatible is everything the marker contract needs:

- **per-object DEKs.** gocryptfs derives every block key from the volume master
  key; adding an envelope key per object changes the header and the format, so
  stock gocryptfs can no longer read it — and the engine no longer needs it to.
- **`fsync` interception.** Markers, copies and parity are enforced at the
  barrier. gocryptfs passes `fsync` through to the backing filesystem and has
  no hook there.
- **manifests and parity sets.** They live beside the ciphertext objects; a
  gocryptfs mount sees a directory of files it does not understand.

So there are two consistent arrangements, and the project must pick one rather
than drift between them:

1. **Pilot / compose** — stock gocryptfs, one mount per workload, key through
   `-extpass`, `-idle` for expiry. No markers, no parity, no per-object keys.
   Cheap, mature, and reversible.
2. **Engine** — the FUSE daemon above. gocryptfs-shaped blocks, envelope keys,
   markers, PAR2, manifests. Not gocryptfs-compatible, and not trying to be.

A third possibility exists and is worth naming only to reject it: keep
stock-gocryptfs **tool compatibility** by keeping the volume master key and
giving up per-object DEKs. That is a legitimate product decision (anyone can
mount the ciphertext with `gocryptfs`), but it throws away per-workload
revocation and rotation at object granularity, so it is not this design.

### One key per volume, and how it handles concurrency

gocryptfs is a **one-key-per-volume** design: a single master key is wrapped in
`gocryptfs.conf` (scrypt or FIDO2) and either supplied through `-extpass` or
`-masterkey`; `-passwd` rewraps it. There is no per-folder key, no
multi-recipient wrap, and no mixed cipher inside one volume — AES-GCM, AES-SIV
or XChaCha20-Poly1305 is chosen at `-init` and applies to the whole cipherdir.

| want | gocryptfs |
| --- | --- |
| several workloads, each with its own key | one volume (one cipherdir, one conf) per workload |
| several keys opening the *same* folder | not supported; the workaround is to give each workload the same master key (wrapped outside gocryptfs), which is one key shared, not several keys |
| per-folder key inside one volume | not supported; nested volumes are the only equivalent |
| mixed schemes (GCM, SIV, ChaCha) in one tree | separate volumes |
| rotation without re-encryption | `-passwd` rewraps the master key; the data key is unchanged |

This is the second reason the engine cannot use gocryptfs as its crypto layer:
a single leaked master key opens the whole volume, and revocation is
all-or-nothing.

On concurrency, the answer has two halves.

- **Within one mount**, concurrency is normal and safe. go-fuse serves requests
  in parallel; a per-file `ContentLock` serialises content operations (write,
  truncate, fallocate) so the block read-modify-write is not interleaved, and
  `fdLock` keeps a descriptor from closing under an in-flight I/O. Different
  files in the same directory proceed concurrently; there is no folder-wide
  lock, and none is needed.
- **Across several mounts or hosts** on the same cipherdir, gocryptfs was not
  designed for it. Since v2.7.0, `-sharedstorage` uses byte-range locks to make
  concurrent access from multiple mounts safe, at a cost: stat caching is off,
  hard links cannot be created, throughput drops, and the man page still warns
  that the mode is less tested. It is not a cluster filesystem.

`-serialize_reads` is a throughput knob for backing stores that perform badly
with concurrent reads, not a correctness control. So "folder-wise concurrency"
needs no explicit lock from the caller: the per-file lock plus the kernel's
semantics cover one mount, and `-sharedstorage` covers several mounts with the
caveats above.

### Composite, not monolith

The draft that put encryption, copy placement, parity, the markers and the
index in one FUSE daemon was the wrong shape. Only one of those has to sit at
the FUSE boundary: the **acknowledgement coordinator**, because POSIX offers no
hook between `write` and `fsync` that can wait for a remote copy or a parity
pass — fanotify has no `fsync` permission event, and an LSM hook that sleeps on
network I/O is not a design. Everything else is a component with a narrow
interface.

| layer | interface | sees plaintext | sees keys | can be separate |
| --- | --- | --- | --- | --- |
| crypto | `seal(plaintext) → object`, `open(object) → plaintext` | yes | the DEK | a library, in-process |
| durability | `put(object, policy) → committed copies`, `get(id) → bytes`, `verify`, `repair`, `drain` | no | no | a daemon or a library |
| index | `record(object, copies, parity)`, `query` | no (opaque ids) | no | a local database, derivable |
| key custody | `unwrap(workload) → KEK` | no | the KEKs | a daemon, off the I/O path |
| FUSE + ack coordinator | `read`/`write`/`fsync`, calls the four above | yes (it is the adapter) | via crypto | must be at the FUSE boundary |

Copies and parity are merged into one **durability** layer on purpose. They
share the object boundary, the domain model, the manifest entry, the commit
order and the repair loop; keeping them apart gives one decision two commit
points. The PAR2 codec stays a pure library inside the layer — the layer
decides *when* to call it (synchronously for a `-fec` folder, lazily at tiering
otherwise), *where* the set goes, and what the acknowledgement waits for.

The consequences are exactly what a composite buys:

- **durability is ciphertext-only**, which is what makes the provider threat
  model true and lets the `object` rung use the same layer without FUSE;
- **its codec needs no key**, so a blind restorer can run verify and repair;
- **the coordinator is thin**: it orders data → copies → parity → manifest and
  implements the markers; it is where the layers meet, not where they are
  implemented;
- **non-FUSE workloads** (S3, git) call crypto and durability directly and get
  an explicit commit — no FUSE, no `fsync` semantics, no markers;
- **each layer is testable alone**: crypto with test vectors, durability with a
  fault-injecting backend, PAR2 with corrupted blocks, the coordinator with
  crash injection.

The cost is one more interface and a commit protocol that spans layers. Keep
them as in-process modules first, with the interfaces above, and split one out
into a service only when its isolation or privilege needs it. The one split
that is worth doing from the start is key custody: it should never be in the
same process as the data path.

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

### When a block fails

gocryptfs is the reference implementation for what a per-block AEAD filesystem
does with damage, and it sets the expectation for our daemon:

- a file is an 18-byte header (version, file id) followed by independently
  encrypted 4 KiB blocks, each with its own 16-byte nonce and 16-byte tag
  (`Documentation/file-format.md`);
- a corrupt block makes a read return `EIO` for every request that touches it.
  The daemon logs the block number, and the rest of the file stays readable
  (`internal/fusefrontend/file.go`, `doRead`);
- a corrupt header makes the whole file `EIO`: the file id is needed to decrypt
  anything, so there is no “rest” to salvage;
- nothing is zero-filled or silently skipped. A recovery tool sees a hole it
  can map: 4 KiB-aligned reads isolate the bad block, and a `ddrescue`-style
  tool copies the rest and leaves the hole behind;
- the failure is per **FUSE request**, not per block. A 128 KiB read that
  crosses one bad 4 KiB block fails as a whole, so a sequential reader that
  issues large reads stops at the gap even though 124 KiB of it were fine. The
  rest is recoverable by re-reading in block-sized pieces, not by the kernel
  retrying;
- detection is all it can do. There is no redundancy inside gocryptfs, so the
  bad block stays bad. `gocryptfs -fsck` enumerates the corrupt files; it does
  not repair them.

That is exactly the gap PAR2 fills: repair the ciphertext block, then let the
AEAD verify it on the next read. It is also why the parity blocks should be
small: the damage unit of the encryption layer is 4 KiB, so a parity block of
64–256 KiB already covers a meaningful run of bad blocks without wasting much
on a single byte flip.

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
engine still records the ciphertext digest, so bitrot is **detected** and
reported — it is simply not repaired locally, because the inner format already
knows how to do that. It also suppresses the background upload and the lazy
parity that a default policy would otherwise schedule; that was the mistake in
the earlier draft, which kept them "best effort".

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
4. the manifest entry — policy, ciphertext digest, per-copy locators, parity
   reference — is written atomically (rename or conditional PUT) and durable.

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
- **Two different checks, two different keys.** The AEAD tag is the authenticity
  check and needs the workload key: it says "these bytes were made by the key
  holder for this object, version and segment". The digest is the identity
  check and needs nothing: it says "these are the bytes this object should be".
  Authentication without the key is impossible; identity without the key is the
  point of storing the digest over the ciphertext.
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
  implementation; PAR3 is a newer specification with better hashing but thinner
  tooling. The contract names the properties, not the binary.

### Implementations, and whether to write one

PAR2 is a published format with several independent implementations; PAR3 is
not ready.

| implementation | language | state |
| --- | --- | --- |
| `par2cmdline-turbo` | C++ | the performance and compatibility reference: ParPar's SIMD backend, roughly 7× stock `par2cmdline` in published benchmarks |
| `libpar2` | C++ | the older library behind several tools; usable, not fast |
| `akalin/gopar` | Go | PAR1 and PAR2, pure Go, with a CLI; the longest-standing Go implementation |
| `hobeone/par2engine`, `javi11/gopar-turbo`, `unxed/par2`, `joamag/parchive-go` | Go | newer pure-Go engines, some with assembly SIMD for the GF(2^16) loop; maturity varies, so read the tests and the issue tracker |
| `mediactl/par2go` | Go + cgo-free shim | wraps `par2cmdline-turbo`'s library through `purego`; gets the mature engine without cgo, at the cost of a prebuilt `.so` |
| `Parchive/par3cmdline`, `par3-rs` | C++, Rust | the PAR3 reference implementation is still in progress and the spec is an alpha draft; `par3-rs` follows the implementation where the two disagree |

For the erasure-code math rather than the PAR2 container, the mature pieces are
Intel ISA-L and `liberasurecode`/`Jerasure` (C, GF(2^8)), `klauspost/reedsolomon`
(Go, widely used and SIMD-accelerated), and `reed-solomon-simd` (Rust). PAR2's
GF(2^16) is what allows up to 32768 blocks per file; GF(2^8) libraries cap the
shard count far lower, which is why a custom GF(2^8) format would need per-chunk
sets.

So: do not write the codec. Use `par2cmdline-turbo` (directly or through
`par2go`) when performance and format compatibility matter, or a pure-Go
implementation when a static binary and no cgo matter more. Writing one is
only justified if the container format has to differ from PAR2 — and then the
GF math still comes from a library, and the blind-restorer compatibility the
format was chosen for is lost.

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
- Three states are reported separately, because they answer different
  questions: the **digest** matches (identity, no key needed), the **AEAD tag**
  verifies (authenticity, key needed, on read), and the **parity** can repair
  the object (bitrot, no key needed). A report that collapses them hides which
  guarantee is actually missing.
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
