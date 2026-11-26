---
id: research-storage-overlay
type: architecture-design
status: draft
title: "The smallest single-node storage system: abstraction ladder, index authority, and what FEC is actually for"
parent: index
references: [index, research-quadronegro-audit, research-quadronegro-design, research-quadronegro-availability-threats, research-files-volumes, research-upkeep-mapping, decision-log]
---

# The smallest single-node storage system

Third revision. The first treated MooseFS as a candidate; the second cut the
distributed half after the correction that the clients are local and the
distributed filesystems are reference only. This one takes three further cuts:

- **abstractions are a ladder, and lower rungs must be earned** — a workload
  that can use git or an object API is not given a filesystem, and a workload
  that can use a filesystem is not given a block device;
- **the index may live in a managed store**, provided the provider can neither
  read it nor change it unnoticed — which also removes the hardest single-node
  reliability problem;
- **FEC is bitrot repair inside a surviving object**, at about 10 % overhead for
  a 5 % recovery target, computed over the ciphertext so a blind restorer can
  verify it. It is not a space optimisation and it does not replace a copy.

Nothing here was run against a live host. MooseFS claims are from the 4.59.2
tree, Longhorn/Rook/Garage claims from their documentation, and the pool facts
from the [audit](quadronegro-at-home-audit.md) and
[design](quadronegro-at-home-design.md) notes in this tree, and the threat
boundary from [its availability register](quadronegro-availability-and-threats.md).

## What the first correction deletes

A distributed filesystem is mostly a solution to *remote clients*. With none,
the majority of the machinery has no referent: namespace RPC, sessions,
exports, per-IP `maproot`/`mapall`, master and metalogger and leader election,
chunkserver heartbeats and grace states, inter-server replication and its
bandwidth limits, rack topology, cross-client cache coherence, and wire
compatibility. The replacements are a local index, a single-writer lock,
per-device queues, and media/provider classes instead of racks.

That is the largest simplification available and it is free. Everything that
survives is a format, a policy, or a local scheduler.

## The abstraction ladder

The second largest simplification is to stop giving every workload the lowest
abstraction it might tolerate. Each rung down costs a front end, a
key-distribution path, an ownership model, and a class of failure that the rung
above does not have.

| rung | workloads | what storage provides | what is **not** needed | cost of granting it anyway |
| --- | --- | --- | --- | --- |
| git | code, config, notes, anything text and versioned | a remote: a forge, or a bare repository whose objects live in the object store | object engine, per-file keys, FUSE, uid mapping | a filesystem per repository, snapshots, backup of working trees, and a merge story the tool already had |
| object | backup agents, sync tools, media pipelines, anything that speaks S3 | one S3-compatible endpoint, a prefix per workload, a KEK per prefix | FUSE, POSIX ACLs, uid/gid, block devices | POSIX emulation, id mapping, and a metadata model for things that only ever did PUT/GET |
| files | applications that only know `open`/`read`/`write`: Transmission, Syncthing, media servers, some databases | one FUSE mount per workload, backed by the same object core | block devices, raw partitions, CSI | a block layer, a filesystem, snapshots, and a device lifecycle |
| block | virtual machines, databases that demand a raw device, a filesystem nested in a container | one LUKS'd LV or zvol bound into the container | CSI, iSCSI, an orchestrator, replication | an entire storage product (Longhorn, Mayastor) plus its control plane |

The rule that follows: **default deny**. A workload declaration names its rung
(`storage: git | object | files | block`), and moving down a rung requires a
stated reason, recorded with the workload. The point is not purity — it is that
each unused rung is a front end, a key path and a failure mode that never has
to be built, tested or restored.

Three consequences worth naming:

- The object front becomes the primary interface. If every workload is `git` or
  `object`, the FUSE front is optional and the block front does not exist.
- Per-workload confidentiality gets *easier* as the rung rises: an S3 prefix
  with a KEK needs no uid mapping, no POSIX ACLs and no FUSE daemon; the
  authority is the key, not the file mode.
- `block` is an exception list, not a tier. A rare VM gets a LUKS'd LV; it does
  not justify a CSI driver, an iSCSI initiator, or a three-node cluster.

The `files` rung's sharing interface and the per-folder durability markers are
specified in [sharing and durability](sharing-and-durability.md).

## What remains of the requirement

The eight properties, restated at the rung where they are cheapest to satisfy.
The earlier draft's wording is kept where it still applies.

| id | as stated | cheapest form | what is cut |
| --- | --- | --- | --- |
| R1 | file-level encryption over plain files | one encrypted object per file plus a per-directory manifest that is itself a plain file | chunk stores, packing, cluster namespace |
| R2 | per-folder/per-object keys, need-to-know | root key → per-workload KEK → per-object DEK; a local key daemon selects by caller (custody in [key custody](key-custody.md)) | KMS service, per-client agents, network auth |
| R3 | FEC plus redundant copies | copies across failure domains for availability; per-segment ciphertext digests for identity and repair; PAR2-style parity over the ciphertext (~10 % overhead) for bitrot | EC across servers, rack-aware layout, k+m shard tables |
| R4 | restore from alternatives, verifiably | a verifier that walks manifests, checks roots and block hashes, restores any object from any copy, repairs bitrot from its parity, and reports what is unrecoverable | replication topology, per-server chunk maps |
| R5 | parallel ops over cold cloud and slow USB SMR | two queue classes with per-device concurrency, and one upload/download queue per provider | global scheduler, cluster load balancing |
| R6 | dynamic expansion and removal | drain a device: copy, verify, wipe; no rebalance across nodes | device removal inside a multi-device filesystem, CRUSH |
| R7 | per-object/folder tiering | three states (hot, cold, trash) plus an age rule per directory | general policy language, labels, export groups |
| R8 | ACLs and uid/gid mapping | mode, owner and POSIX ACL entries in the manifest, resolved per workload at mount — **only for the `files` rung** | network idmapping domains, per-subnet identity |

R8 shrinks with the ladder: `git` and `object` workloads have no uid/gid
problem at all, and their access control is the KEK plus the prefix policy.
Only the `files` rung needs POSIX ownership, and only the `block` rung needs a
device.

## FEC, restated

Two corrections since the first draft. FEC is not a space optimisation: it is
**bitrot repair inside a surviving object**, at about 10 % overhead for a target
of about 5 % recoverable, and more parity than that buys nothing because an
object that has lost more than a few percent of its blocks needs a copy, not
more parity. And the parity is computed over the **ciphertext**, so a restorer
who holds only the objects and the parity can verify that a repair produced the
right bytes without ever holding the key.

| job | what answers it | what it cannot answer |
| --- | --- | --- |
| availability | copies in independent failure domains | which copy is correct |
| integrity | authenticated ciphertext (keyed) plus per-segment ciphertext digests (keyless) | which segment is bad, without the key |
| bitrot repair | PAR2/PAR3 parity over the ciphertext, ~10 % overhead | a deleted or largely missing object |
| space | nothing — parity costs 10 %, a second copy costs 100 % | any of the above |

How it works, and what it does not do:

- PAR2 splits an object into fixed blocks, hashes every block and the file,
  and adds recovery blocks. `verify` names the bad blocks without the key;
  `repair` reconstructs as many blocks as there are recovery blocks.
- 10 % overhead means at most 10 % of the blocks are recoverable. The design
  target is 5 %, leaving margin for parity that itself rots and for the blocks
  a repair consumes. A wholly missing object needs 100 % parity, which is why
  a second copy is cheaper than trying to encode one.
- Block size is the granularity of the waste: 64–256 KiB keeps a single bad
  byte from condemning much data, while PAR2's per-file block limit (32768)
  sets the floor for very large objects — a 1 GiB object is 4096 blocks at
  256 KiB, a 1 TiB object needs 32 MiB blocks.
- Order is encrypt → object → parity over the ciphertext → manifest. Parity
  over plaintext would leak linear combinations and would need the key to
  verify.
- The object id is opaque and the PAR2 packets carry that id, the size and the
  hashes, not the plaintext name — so the parity set is blind-verifiable
  without becoming a metadata leak.
- `par2cmdline-turbo` is the mature implementation; PAR3 is a newer
  specification with better hashing but thinner tooling. The contract names
  the properties, not the binary.

It does not replace replication. Ten percent parity inside one host is one
failure domain: a lost device takes the object and its parity together, and a
copy is still the only thing that survives that. The composition is:
**copies for availability, authenticated ciphertext for integrity, PAR2 for
bitrot, and no erasure coding across domains.**

### AEAD, digests and what each one proves

The encryption is AEAD, so it *does* authenticate the segment it just read —
with the key, and only within the scope the associated data declares. A digest
is not a second authenticity check; it answers different questions. Keeping the
two apart is what prevents both an unnecessary plaintext hash and a false sense
of freshness.

| mechanism | key needed | proves | cannot prove |
| --- | --- | --- | --- |
| per-segment AEAD tag | yes | these bytes were produced under this key for this object, version, segment index and count, when the AAD binds them; any change fails closed | freshness; which of two authentic copies is current; anything at all to a holder without the key |
| per-segment ciphertext digest | no | the exact bytes expected at this index; which segment is bad | authenticity — a digest can be recomputed by anyone |
| whole-object ciphertext digest (root over the segment digests) | no | this is exactly the committed object, and two copies match | freshness without an anchored version; that the plaintext is the right plaintext |
| PAR2 block hash | no | a repair produced the right ciphertext block | authenticity |
| signed manifest head and monotonic version | owner key | the object-to-digest mapping is current, and an old consistent tree is a replay | plaintext correctness |

Three consequences:

- **Per-segment AEAD, not one tag for the file.** A single whole-file tag would
  force reading and verifying the entire object before serving the first byte.
  Per-segment tags keep random access, provided the AAD binds the object id,
  version, segment index and segment count — without those, truncation,
  reordering and mix-and-match all look authentic.
- **The digest is over the ciphertext.** That is what makes it checkable
  without the key: a blind restorer recomputes it, PAR2 hashes the same bytes,
  and two copies can be compared. A digest over the plaintext would need the
  key, would leak equality if it were ever used as an id, and is redundant for
  authenticity because the AEAD tag already covers those bytes.
- **The digest is identity, not authenticity.** It says "these are the bytes
  this object should be", not "someone holding the key made them"; and alone it
  says nothing about freshness. The signed head with a monotonic version
  supplies the missing part.

If a plaintext digest is kept at all, it belongs inside the encrypted header —
useful for comparing a restore to its source during a migration, never exposed
as an id.

## The index and where it lives

The index — names, sizes, owners, key references, copy and parity locations — is the most
sensitive and the least recoverable part of the system. It has two possible
roles, and the choice decides how much a managed database helps.

**Derivable index (recommended default).** The manifests are the truth: plain
files, encrypted, signed, with a Merkle root over extents. The index is a
rebuildable cache (SQLite, or anything else) that answers queries quickly. Its
loss costs a rebuild, not data. Reliability becomes a performance property, and
the single-node failure the earlier draft worried about mostly disappears.

**Authoritative index (when the object count makes rebuilds painful).** Then
the index must never be lost, and a managed store is exactly the right tool:
backups, point-in-time recovery, failover and geo-replication stop being
homework. The price is a provider in the trust boundary, and the design must
make the provider unable to read or silently change it.

| design | provider can read? | provider can change unnoticed? | cost |
| --- | --- | --- | --- |
| client-side encryption, ciphertext rows or blobs | no | no, if every row is MAC'd and the snapshot has a signed root and monotonic version | no server-side plaintext queries; lookup by id or blind index only |
| tamper-evident append-only log (immudb, Trillian/Rekor, a signed JSONL chain) | no, if entries are encrypted | no — inclusion and consistency proofs make any rewrite evident | a log to compact, and proofs to verify on read |
| TEE-backed database (Azure SQL with secure enclaves, Nitro Enclaves, Confidential Containers) | no, even during query | no, if attestation is verified and the code is pinned | attestation infrastructure, SKU/region limits, side channels, and freshness still needs a versioned signed root |

The third row is the only one that preserves server-side queries over
plaintext, and it is the only one that earns the words "confidential
computing". The first two are cheaper and sufficient for an index, whose
queries are lookups and range scans over ids and hashes — not `LIKE '%name%'`.

Three rules keep a managed index honest:

1. **The provider must not be on the write path.** A local embedded database is
   authoritative for reads and writes; replication is asynchronous. A home
   internet outage must not stop the pool.
2. **Freshness is the client's job.** A TEE proves which code ran, not that the
   answer is current. A monotonic version and a signed root are still required
   to detect a replay of yesterday's consistent snapshot.
3. **The index is encrypted as a whole,** not just the payloads in it. Names
   and directory structure are the leak; object counts and sizes are the
   residue to accept or pad.

If SQL is not actually needed, the leanest managed store is not a database at
all: a bucket with versioning and object lock, holding the encrypted index log
and periodic signed snapshots. It gives durability and immutability with no
server to trust for query semantics.

## What survives from the reference models

The reference systems are specifications to lift, not products to deploy.

| idea | source | keep or cut |
| --- | --- | --- |
| storage classes: `KEEP`/`ARCHIVE`/`TRASH`, archive delay, minimum size, priority | MooseFS `mfsscadmin(1)` | keep as the per-directory policy schema |
| per-device removal markers (`*`, `<`, `>`) and absolute/reserve/percent space limits | MooseFS `mfshdd.cfg(5)` | keep as the drain and capacity model |
| per-block checksums and a background scrub | MooseFS chunk CRC, HDFS block scanner | keep, per object, per extent and per PAR2 block |
| encryption zones: the directory is the policy boundary | HDFS transparent encryption | keep the boundary; cut the KMS |
| HOT/WARM/COLD/ARCHIVE chosen per directory | HDFS archival storage | keep, as the three-state tier |
| named erasure policies per path (`RS-6-3`, `RS-10-4`) | HDFS erasure coding | keep the naming; apply to cold data |
| capability = key | Tahoe-LAFS | keep the model; implement as a wrapped DEK |
| hot copies, background EC on warm data | SeaweedFS `README` | keep the transition; cut the cluster |
| EC pools with `deviceClass` selection (hdd/ssd/nvme) and a replicated metadata pool | Ceph via Rook | keep the shape; too heavy to run here, and its EC needs OSDs across failure domains |
| a layout of zones, capacities and weights with a resync protocol — **and an explicit refusal of EC because it complicates placement** | Garage | keep the layout/resync model; note the opposite choice on EC |
| encrypted content-addressed packs with index, verify and prune | restic `doc/design.rst` | adopt as a component for cold data |
| FEC as ordinary files needing no daemon | par2 | adopt over the ciphertext for `-fec` folders and cold packs |
| verified append-only history | immudb, Trillian, Rekor | adopt as the tamper-evidence model for the index |
| file-level AEAD and name encryption behind FUSE | gocryptfs | adopt the block format and the per-block failure behaviour, not the volume-master-key model |

Cut from the reference models entirely: master/chunkserver/volume-server
processes, wire protocols, sessions, export authentication, rack topology,
leader election, cluster membership, and every HA mechanism whose failure mode
is a network partition.

Two of these are worth a sentence. Garage is the best prior art for *placement
across heterogeneous media* — a layout with zones, capacities and weights, and
a block-resync protocol — and it deliberately refuses erasure coding because
coding makes placement and synchronisation harder. That is the honest cost of
erasure coding, and this design takes only the much smaller cost of PAR2 bitrot
parity. Rook is the best prior art for the *whole policy stack* (EC pools,
device classes, object store, replicated metadata), and it needs a Kubernetes
cluster and OSDs in separate failure domains — which is the same "five distinct
chunkservers" problem in a different costume.

## The minimal system

Six pieces, one process boundary, four optional fronts.

| piece | job | smallest implementation |
| --- | --- | --- |
| object format | one file → header + ciphertext (+ optional PAR2 set) + manifest entry | versioned header, AEAD with AAD binding id/version/segment index and count/name/length, Merkle root over segment ciphertext digests |
| index | resolve object, copies, keys, state | SQLite cache over manifests; optionally replicated encrypted to a managed store |
| key daemon | hold the root key, unwrap KEKs, select by caller | systemd service, credential-loaded root key, unix socket, uid check |
| backends | read/write on each medium | adapter per class: local dir, USB/SMR append-only pack, S3-compatible, cold |
| placement/tier | hot/cold/trash, copy targets, age rules | a table per directory plus a queue |
| verifier/repairer | hash, decode, re-encode, report | a timer job with a report file, like `restic check --read-data` |

Fronts, each enabled only when a rung exists: an S3-compatible endpoint for
`object`, a FUSE mount for `files`, a LUKS'd LV/zvol for `block`, and nothing at
all for `git` (a bare repository in a bucket is enough).

The data path is short and testable:

- **write**: encrypt → write to the hot backend → (PAR2 over the ciphertext for
  a `-fec` folder) → commit the manifest entry in one atomic act → enqueue the
  copy.
- **read**: resolve → read the nearest copy → verify → decrypt; a damaged block
  is repaired from its parity, a missing copy is restored from another.
- **scrub**: walk manifests by age, verify every copy, repair bitrot where the
  parity allows, record the last-good time and the block state.

The failure model is narrower than a cluster's, which is the point: process
crash, device loss, bit rot, provider outage, key loss, host loss. No
partitions, no split brain, no stale caches.

## Layer cuts worth taking

| cut | removes | costs | verdict |
| --- | --- | --- | --- |
| Btrfs multi-device RAID1c2 → one filesystem per device | degraded mounts, `btrfs device remove`, ENOSPC on rebalance, USB correlation | placement and copies move up | take it |
| LUKS on media that already holds only ciphertext | the unlock/park lifecycle, the Infisical fetch, the member sweep | one defence-in-depth layer if the object layer has a bug | take it for cloud and cold; keep it on hot local disks |
| per-workload key agents → one key daemon | N services, N sockets, N upgrades | one process holds every KEK | take it |
| EC across latency domains → parity per object, copies across domains | repair reads from cold storage | cloud stores a full copy, not a share | take it |
| the PVC abstraction | the provisioning layer | nothing on one host: a PV is a directory and a bind | take it; [the volume research](files-and-volumes.md) already records that the minimal provisioner is mkdir/rm |
| CoW filesystems on SMR | random-write amplification | no snapshots on that disk | take it: append-only packs on ext4 |
| FUSE for every workload | a daemon, a mount graph, an ownership model | only the `files` rung remains | take it with the ladder |
| block storage for non-block workloads | CSI, iSCSI, a storage product | none | take it; a LUKS'd LV covers the exceptions |

Not to be cut: per-device filesystems. The object layer's promise is that the
bottom of the stack is still files, readable by `dd`, `rsync`, `restic` or a
file restorer. Raw block and log-structured-on-raw layouts save a layer and
destroy the property the brief puts first.

## k3s, k0s and Longhorn after the ladder

The ladder changes the answer, because it removes most of the demand those
products serve.

**k3s / k0s** collapse orchestration: real PV/PVC/CSI, a scheduler, declarative
workloads, operators. They cost a control plane — API server, kine/SQLite (k3s
defaults to SQLite; k0s to SQLite for a single node and etcd for multi),
kubelet, containerd, CNI, kube-proxy, CoreDNS, and in k3s's default bundle
Traefik, ServiceLB, metrics-server and local-path-provisioner. On one host the
PVC API resolves to `mkdir` plus a bind, so it buys ergonomics, not capability.

**Longhorn** is block storage: replicas over iSCSI, `open-iscsi`/`nfs-common`,
per-volume LUKS with the key in a Kubernetes Secret, CSI snapshots and block
backups, and erasure coding only in the V2 engine's experimental *sharded*
layout (which the project's matrix excludes from backup/restore, cloning and
DR). With `block` demoted to an exception list, Longhorn has no customer left
here.

**Rook/Ceph and Garage** are the better object-store prior art, and both are
reference only: Rook needs a cluster and OSDs in separate failure domains;
Garage is lightweight and honest but refuses EC, so it cannot serve R3's
diagnosis requirement.

The collapse that works is the ladder itself: fewer rungs, fewer fronts, no
storage product for the common case. If a block workload ever appears, the
leanest deployment is a LUKS'd LV or zvol bound into the container — no CSI, no
iSCSI, no orchestrator. Longhorn with one replica is the next step up if CSI
semantics are genuinely needed; Mayastor is a project, not a volume.

## Compose first, build second

Most of R1–R5 is available today from mature parts, arranged along the ladder:

| rung | component | gives | does not |
| --- | --- | --- | --- |
| git | a forge, or a bare repo in a bucket | integrity, versioning, review | large binaries (git LFS pushes them to `object`) |
| object | restic to two backends; rclone to two providers | encrypted packs, index, `check --read-data`, prune, per-file restore | live POSIX, per-object bitrot parity |
| object, cold | par2 over the ciphertext | repair and verification without a daemon or the key | batch, offline, no placement |
| files | one gocryptfs mount per workload, key in a systemd credential | per-file AEAD, encrypted names, kernel uid checks | one key per mount, no markers, no parity, no per-object keys, structure leaks |
| block | a LUKS'd LV or zvol bound into the container | a raw device without a storage product | snapshots, replication |
| index | the manifests plus a local SQLite cache; optionally replicated encrypted to a managed store | a rebuildable index, offsite durability | server-side search over plaintext |

That composition covers R1, R2 (per-rung keys), R3 for cold data, R4 with
`check`, and R7 by directory convention. Its gaps are exactly the reasons to
build: per-object tiering inside a live tree, one index that can answer "where
is every copy of X", a cold retrieval state machine, keys that are issued
rather than mounted, and a partial-recovery report per file.

Run the composition as a pilot. It produces the measurements — FUSE cost,
encrypt-and-encode cost, cloud retrieval behaviour, restore time — that any
engine design would otherwise guess at, and it is reversible.

## What would be necessary if the engine is built

- **Decisions, written down:** which failure domains exist and how many may
  fail; whether host root is inside the threat model; whether the index is
  derivable or authoritative and which managed store holds it; whether the
  provider is trusted, TEE-attested, or ciphertext-only; which workloads are
  allowed below `object`.
- **Artifacts:** object and manifest format with a ciphertext digest tree and a test
  vector; key-wrap format; backend capability profile (rename, conditional PUT,
  `fsync`, max object size, latency, cost, write pattern); commit/GC protocol;
  scrub/repair protocol with a partial-recovery report; tier state machine;
  restore runbook; the workload rung policy.
- **Components:** the six above, plus the S3 front (required), the FUSE front
  (optional), and the block front (an exception, not a product).
- **Tests, not claims:** kill the process mid-commit; pull one device; make one
  provider return 500s; corrupt a block and prove the verifier names it and the
  parity repairs it; lose
  the index and rebuild from manifests; replay an old signed root and prove it
  is rejected; lose a key and prove the rest still opens; restore on a clean
  host from ciphertext, manifests and the key alone; fill the pool to ENOSPC;
  migrate one workload and roll back.
- **Rough effort:** format and crypto two to three weeks; backends one to two;
  commit/GC/verify three to four; tiering and drain one to two; failure testing
  two to three. The FUSE front is zero for the pilot (gocryptfs is the layer)
  and months for the engine (the layer that can enforce markers); the index
  replication is days if the manifests are the truth and weeks if they are not.

## Issues that will bite

1. **Crash consistency is the whole game.** A commit is one atomic act — a
   manifest rename or a conditional PUT — after the object, and its parity, is
   durable. Any
   other ordering leaves an object that looks present and is not.
2. **Authority over the index, not just its reliability.** If the index is
   derivable, a managed store is a convenience; if it is authoritative, the
   provider is in the trust boundary and freshness, encryption and signed roots
   are mandatory. Decide which, and write it down.
3. **Replication without an anchor is theatre.** Two copies that disagree are
   two claims; only a hash anchored outside both decides. The signed head is
   not optional.
4. **Parity stays with its object.** A repair that reads parity from cold
   storage takes as long as the object does; keep the parity set next to the
   object, and treat copies as the availability mechanism, not parity.
5. **Cold retrieval is not POSIX.** Object stores make you ask, wait, then
   read. Model a retrieval state and let reads block with a deadline, or expose
   `recall` and accept that the POSIX view is warm-only.
6. **Encryption mistakes void the guarantee:** nonce reuse, AAD that does not
   bind name and version, keys in swap or core dumps, replay of an older
   consistent snapshot, and dedup leaking equality across workloads. Each is a
   decision and a test.
7. **A TEE is not a freshness proof.** Attestation says which code ran, not
   which version it answered from; a monotonic counter and signed root are
   still required.
8. **SMR hates rewrites.** Append-only packs, zone-aligned writes, no CoW
   filesystem, no in-place object repair — rebuild into a new object and retire
   the old one.
9. **FUSE is an operational surface:** `RequiresMountsFor=` does not order a
   userspace mount, a hung daemon puts `umount` in `D` state, rootless Podman
   needs the mount on the host, and SELinux wants a label. The ladder is the
   mitigation: fewer workloads need it.
10. **Small files force a choice:** one object per file keeps R1 and multiplies
    metadata; packing fixes the waste and breaks it. Decide per size class.
11. **Governance is a feature.** A rung policy that is not enforced becomes a
    suggestion; the declaration must be validated and the exception list
    reviewed, or every workload drifts back to `files`.
12. **Migration still costs what it cost before:** xattrs, ACLs, hardlinks,
    sparse files, sockets, a per-file hash comparison, a two-way window and a
    rollback. The unresolved UUID and mount-point questions in the audit come
    first.
13. **Operating it alone:** one more daemon to monitor, upgrade, back up and
    restore, with no distro package and no upstream. That is the real price,
    and it belongs in the decision.

## Verdict

Three branches, in increasing order of work.

**A. Withdraw the advanced priorities.** If what is wanted is "PV/PVC without
hand-written scripts, snapshots, and an offsite copy", then k3s/k0s + Longhorn
is the smallest supported answer, with per-volume LUKS and S3 backups. It is
block storage: no per-file keys, no file-level parity, no plain-file restore.
Choose it deliberately, not as a step towards the brief.

**B. Keep the priorities, stay single-host, compose first (recommended).**
Keep LUKS and one filesystem per device; drop RAID1c2. Sort the workloads along
the ladder — `git` and `object` first, `files` only where the application
demands it, `block` as an exception. Run gocryptfs per `files` workload in the
pilot — mount-scoped key, `-extpass` for the injector, `-idle` for expiry — and
accept that markers do not exist there; the engine replaces it when they are
needed. Restic to two backends for cold and backup, par2 over the ciphertext
where bitrot repair is wanted, rclone for the offsite copy, systemd timers for
scrub and tiering. Put the index on the
manifests with a local cache, replicated encrypted to a managed store only if
rebuilds become painful. Build only the glue: key wraps, a verify/drain tool, a
partial-recovery report.

**C. Build the small engine, only if B's gaps are the blockers.** One daemon,
one derivable index, per-device backends with capability profiles, a key
daemon, a verifier with an extent map, an S3 front and an optional FUSE front.
No master, no chunkserver, no protocol, no quorum, no remote client. MooseFS,
Rook, Garage and Longhorn remain specifications; Longhorn only returns if a
block workload appears.

What the three cuts bought: the network is gone, most workloads never touch a
filesystem, the index's reliability is either trivial (derivable) or bought
from a provider with the confidentiality made explicit, and FEC is aimed at the
question it actually answers — which blocks are good, and can the bad ones be
rebuilt without the key.

## Open questions

1. Which workloads can be lifted to `object` or `git`, and which genuinely need
   `files`? That inventory decides whether the FUSE front exists.
2. Is the index derivable from manifests at acceptable cost, or authoritative?
   The answer decides whether a managed database is needed at all.
3. If managed: is ciphertext-only acceptable, or is server-side query (and
   therefore a TEE with attestation) required?
4. Which failure domains exist — disks, controllers/hubs, hosts, providers —
   and how many may fail at once?
5. Is host root inside the threat model? If yes, per-workload keys protect
   against the provider and a stolen disk only. Settled for this pool in the
   [VM note](microvm-composition.md): the host is trusted on purpose, and
   inspecting a guest is a feature.
6. How long may a cold read block, and is a two-step `recall` acceptable?
7. Is deduplication wanted? It conflicts with per-workload keys.
8. Does any workload actually need `block`? If none does, Longhorn and Mayastor
   leave the document entirely.

## Status

Draft assessment, third revision. Distributed filesystems are reference only;
no deployment of MooseFS, Rook, Garage, k3s, k0s or Longhorn is proposed. No
host was queried, no key was handled, and nothing under `bin/`, `config/` or
`~/unraid-at-home/` was changed for this note.
