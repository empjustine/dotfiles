---
id: research-key-custody
type: architecture-design
status: draft
title: "Key custody: TPM, a remote injector, and what cold boot defeats"
parent: index
references: [index, research-quadronegro-availability-threats, research-storage-overlay, research-sharing-and-durability, research-microvm-composition, research-multi-uid-access, decision-log]
---

# Key custody: TPM, a remote injector, and what cold boot defeats

The question: would fetching the credentials that decrypt the pool from a
second trusted computer over SSH be better than TPM-sealed credentials against
a physical adversary with full hardware access, and would either stop a cold
boot attack?

The short answer:

- **Against a stolen disk or a powered-off machine**, a remote injector *with
  attestation* can be at least as good as a TPM keyslot, and better when the
  TPM is a firmware TPM or the boot chain is not measured. A naive SSH injector
  that authenticates with a host key stored on the target's disk is **worse**
  than a TPM keyslot: the key file travels with the disk.
- **Against a running machine**, neither helps. Cold boot, DMA, or simply using
  the unlocked machine gets the key *and the plaintext* from RAM. The injector
  changes where the key was kept, not whether it is resident while the pool is
  open.
- **Cold boot is not a key-custody problem.** It is a memory-exposure problem.
  The real defences are not having the key in RAM when the machine is seized,
  encrypting RAM, or preventing the seizure.

This note develops the cold-boot and DMA rows of the
[availability and threat register](quadronegro-availability-and-threats.md)
and the key hierarchy in the [storage note](storage-overlay.md). Nothing was
run; the hardware questions are the ones the register already lists.

## Split the threat by machine state

"Full hardware access" is not one attacker. What is exposed depends on the
state the machine is in when it is taken.

| state | what the attacker gets | what actually protects |
| --- | --- | --- |
| powered off, disks removed | ciphertext only | at-rest keys: TPM keyslot, remote-only key, strong passphrase |
| powered off, machine taken whole | the machine can be booted; a TPM keyslot unseals if the boot state matches; a remote key needs the injector to release it | measured boot + PCR policy, Secure Boot, disk-only secrets, injector attestation |
| booting, attacker controls media | their own kernel, then the disks; a TPM keyslot refuses if PCRs differ; a remote key needs the injector's cooperation | firmware lockout, external boot disabled, Secure Boot, PCR policy, injector policy |
| running, pool mounted | the key and the plaintext are in RAM and in the page cache | nothing cryptographic; only unmounting, memory encryption, or physical prevention |
| suspended to RAM (S3) | the same as running, with hours of unattended exposure | do not use S3; power off or hibernate with encrypted swap |

The register's conclusion stands: a patient opponent with the machine in hand
wins. The useful goal is to make the *at-rest* states safe, shorten the
*unlocked* window, and make tampering visible.

## What TPM sealing actually gives

A TPM2 keyslot or a sealed credential binds a secret to **that TPM** and,
optionally, to **the measurements in named PCRs**. Unsealing requires the same
TPM and the same boot state; the sealed blob is useless on another machine.

What it buys:

- a stolen disk is useless, even with the host root filesystem;
- with Secure Boot and measured boot, tampering with the initrd, UKI or kernel
  command line makes the unseal fail instead of silently leaking;
- an optional PIN turns "possession of the machine" into "possession plus
  knowledge", with TPM anti-hammering as a brake.

What it does not buy, and why the register says "TPM sealing without measured
boot still gives power button equals plaintext":

- **A machine-in-hand attacker can boot it.** Without a PIN, the TPM will
  unseal for them as readily as for you. With a PIN, they can attack the PIN,
  the TPM bus, or the firmware.
- **A firmware TPM trusts firmware.** Intel PTT and AMD fTPM run on the
  platform; an evil-maid firmware update can compromise the TPM itself, and
  then the measurements are whatever it says.
- **A discrete TPM is a bus device.** Interposers, glitching and replay
  research exist; a TPM raises the cost, it does not make the key
  non-extractable against a lab.
- **Clearing the TPM is a denial of service.** The data survives; the unlock
  path does not. The recovery passphrase in a separate keyslot is what keeps
  that from being a data-loss event.
- **PCR brittleness.** Firmware, db and kernel updates move PCR 7 and lock the
  token out. That is a re-enrolment chore, and it is why the passphrase stays.
- **Nothing about RAM.** Once unsealed, the key is a process buffer like any
  other. The TPM protects it before and after, not during.

## What a remote injector gives

A second trusted machine that holds the KEKs and releases them on request moves
the secret **off the machine that holds the data**. If the target's disk is
stolen, there is nothing on it to unseal; the injector will not answer because
the machine is not there. That is a real gain, and it is strictly better than a
key file in Infisical fetched with a token that also lives on the host.

Its strength, however, is entirely the strength of its **authentication of the
caller**:

| how the target authenticates | what a stolen disk can do | verdict |
| --- | --- | --- |
| SSH host key stored on the target's root filesystem | copy the key, impersonate the machine, ask for the key | worse than a TPM keyslot |
| host key sealed to the TPM and only usable on an attested boot | boot the machine, unseal, impersonate | equal to a TPM keyslot |
| TPM quote over PCRs plus a fresh nonce, verified by the injector, bound to a workload identity | nothing without the TPM and the expected measurements | better than a TPM keyslot, and auditable |

The last row is the one worth building. It also has to bind the release to the
**workload**, not just the host: otherwise a compromised container asks for the
pool's KEK and receives it. The injector should know which unit is asking (its
attested identity, its cgroup, or a vsock channel owned by that unit) and
release only that unit's KEK.

What the injector adds beyond key custody:

- **policy**: a time window, a rate limit, a human approval for a new workload,
  a refusal outside maintenance hours;
- **audit**: every release is a log line with an identity and a reason;
- **rotation and revocation** in one place, without touching the target;
- **a smaller blast radius per incident**: revoke one workload's KEK instead of
  re-keying the pool.

What it costs:

- **a new trust anchor**: the injector holds every KEK, so it is the highest-value
  target in the system. It needs its own TPM/HSM, its own hardened boot, and
  its own backups;
- **a network dependency**: no injector, no unlock. The recovery path must be
  offline and tested, or a broken link becomes an outage;
- **the same RAM exposure**: after release, the key is in the target's memory
  exactly as a TPM-unsealed key would be;
- **inherited trust in the quote**: the injector verifies the boot state *it is
  told about*, as the register puts it. If the TPM or firmware lies, the
  injector is satisfied.

Prior art worth reading: Clevis/Tang (network-bound disk encryption — the key is
not on the disk, but Tang does not attest the client, so a machine on the
network can unlock), Keylime (TPM quote verification and key release to
attested agents, the closest match to the "attested injector" idea), Vault or
OpenBao with AppRole/mTLS (policy and audit, no hardware attestation by
default), SPIFFE/SPIRE (workload identity, with node-attestation plugins), and
cloud KMS instance-identity flows.

## Cold boot, specifically

Cold boot attacks exploit **DRAM remanence**: memory contents survive for
seconds after power loss at room temperature, and much longer when the chips
are cooled. The attacker freezes or transplants the DIMMs, reboots into a
custom kernel (or reads the chips elsewhere), and dumps memory.

It defeats **both** mechanisms in the question, for the same reason: by the
time the attacker dumps, the key has already been unsealed or delivered and is
sitting in the daemon's address space. The origin of the key is irrelevant. The
dump also contains the page cache and the FUSE buffers, so the attacker gets
**plaintext**, not only the key.

Suspend-to-RAM makes it worse: S3 keeps memory powered, so the key sits there
for as long as the machine sleeps. Hibernation writes memory to disk; if swap
is not encrypted, that is a disk leak, and if it is, the key needed to resume
must still come from somewhere.

What actually helps, in order of value:

1. **Shorten the exposure.** Unmount the pool when no workload needs it — the
   existing parked state is a security control, not only an ordering device —
   and drop the page cache and the daemon's buffers on unmount. A machine that
   is seized with the pool parked has no key and no plaintext in RAM.
2. **Do not use S3.** Power off, or hibernate with encrypted swap and a key
   path that is not resident afterwards. On a desktop, "sleep" is the single
   worst setting for this threat.
3. **Short-lived keys.** Per-workload KEKs fetched at mount and expired at
   unmount; a small DEK cache with a hard TTL; `mlock` plus explicit zeroing of
   key buffers; no core dumps; no plaintext swap.
4. **Memory encryption, if the hardware has it.** AMD SME/TSME or Intel TME
   encrypt DRAM with a key generated at boot, so a transplanted or
   cold-booted image is not readable on another machine (a warm reset is the
   edge case to check). A confidential VM (SEV-SNP or TDX) for the daemon goes
   further and protects it from the host — at the cost of the host's ability to
   inspect it, which the [VM note](microvm-composition.md) treats as a feature.
5. **Physical controls.** Chassis intrusion switch wired to power-off, tamper
   evidence, and — where the threat justifies it — soldered or epoxy-covered
   memory. These raise cost and give notice; they do not make the attack
   impossible.

What does not help: a TPM keyslot by itself, an injector by itself, full-disk
encryption by itself, "the key never touches the disk" (true, and irrelevant
once it is in RAM), memory wiping on clean shutdown (the attacker pulls power),
and Secure Boot (boot integrity, not memory).

## The plaintext, not just the key

The attacker wants the plaintext. While the pool is mounted, the plaintext is
in the page cache, the FUSE daemon's buffers and the workload's memory. A cold
boot dump therefore yields data even in the improbable case where the key is
somehow absent. Two consequences:

- the exposure window is the **mount lifetime**, not the key-fetch moment, so
  idle unmounting and cache dropping are the highest-value controls;
- "the key is protected" is not the same claim as "the data is protected". The
  design should state which one it means.

## Verdict for this pool

- **Keep the TPM2 keyslots, Secure Boot and the PCR policy for the disks.**
  They are cheap, offline, and make a stolen disk useless and a tampered boot
  loud. They are not a defence against a running machine.
- **Add a remote injector only for the per-workload KEKs, and only with
  attestation and workload binding.** It is better than a key file on the host,
  equal to a TPM keyslot if it trusts a file-based SSH key, and better than
  both if it verifies a TPM quote bound to the request. It is not a replacement
  for TPM disk unlock: it adds a network dependency and a second high-value
  target.
- **Write down that a seized running machine is game over**, and that cold boot
  is out of scope unless the hardware offers memory encryption. The register
  already says this; the key design should not quietly imply otherwise.
- **Shorten the window as the primary control**: park the pool, unmount on
  idle, drop caches, expire KEKs, and avoid S3 sleep. This is worth more than
  any choice between TPM and injector.

## What would be necessary to test it

- **Stolen-disk test**: disks plus the host's SSH key, injector refuses because
  the request is not attested.
- **Boot-tamper test**: change the initrd or kernel command line; the TPM
  unseal fails, the attestation quote does not match, no key is released, and
  the failure is loud on both sides.
- **Injector-offline test**: the documented recovery path works without the
  injector, and it is not a copy of the same key on the same host.
- **Cold-boot drill** (controlled, on a spare machine): seize a running pool,
  freeze/reboot into a memory dumper, and record what is recoverable. The
  result belongs in the register; it is the only way to know whether the claim
  is true.
- **DMA test** with the IOMMU on and off, and with Thunderbolt authorization
  on and off.
- **Idle test**: after the pool is parked, the daemon no longer holds the KEK
  and the page cache no longer contains plaintext.
- **TPM-clear test**: the recovery passphrase still opens the disks.
- **Rotation test**: revoke one workload's KEK and prove the others still
  mount, and that the revoked workload cannot.

## Open questions

1. Does the host have a discrete TPM 2.0 or a firmware TPM, and which PCRs
   survive its updates? The register already asks; the answer decides how much
   the TPM is worth.
2. Does the CPU support SME/TME, SEV-SNP or TDX, and is it enabled in firmware?
   Without memory encryption, cold boot is not defensible.
3. Is a second machine's availability dependency acceptable, or is a TPM-only
   design with a short window and an offline recovery path the better trade?
4. What identity does the injector trust for a workload — an attested unit, a
   cgroup path, a vsock channel, or a combination?
5. Does the injector itself have an HSM or TPM, and who can approve a release?
6. Is suspend-to-RAM disabled on every host that can mount the pool, and is
   the setting enforced rather than documented?

## Status

Draft design note. Nothing was enrolled, fetched, compiled or seized. The TPM,
cold-boot and DMA material is from the register and the general literature; the
injector options are drawn from the prior art named above.
