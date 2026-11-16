# Rebuilt C0 provenance substitution

Date: 2026-11-15. Decision owner: project owner, explicit authorization in the
28-A1 engineering conversation. Status: **ACCEPTED WITH DISCLOSURE**, an owner
disposition rather than a technical test PASS.

The owner accepts the specifically authenticated rebuilt C0 as the designated
historical bootstrap seed for Astra's first release process. Recreating the
lost original executable byte for byte is no longer a prerequisite solely for
its provenance identity. Subsequent release engineering may use the rebuilt
seed's authenticated source/toolchain/build identities together with the
separately qualified self-hosting generation chain.

The live designated replacement is
`~/Workspace/codex/work/astra/build/selfhost27b/c0-recovery-safealloc2/astrac`,
114,412,096 bytes, SHA-256
`19d744c828551b2184f06552740db1beb5b6eeb326b8e98ba56d2dfa5bca31b6`.
Its source, Meson recipe, generated C and tool/build/qualification receipts
remain preservation obligations; this decision does not authenticate an
arbitrary substitute with the same filename.

The 28-A1 audit rehashed all **338** inputs in the retained replacement build
receipt without mismatch. Its recorded source HEAD is
`e750030baa139481d89946b2b2182dbe72628d31`. The retained recipe
`runtime/selfhost27b-recovery/c0-build-safealloc2.py` has SHA-256
`38db0750cf3ed52fd6ad667a22061de21258dc18547efccb633cbe7820afc315`;
the associated `c0-build-safealloc2/result.json` has SHA-256
`dd568960d3943d198b4daae8671f2581c12be5013db9e93857ae18ae211a9ed4`.
These runtime paths are relative to `~/Workspace/codex/work/astra/` and remain
external dependencies, alongside the unchanged build tree and tool capsule.

The retained independent `c0-qualification3/result.json` has SHA-256
`469e729c3d2d8562a385d095b69904838021e54c88dd46bdfaca18fe597373e7`.
Its strict process-memory check exited **99**, with no suppression, invalid
access or definitely/indirectly/possibly lost bytes recorded, but reachable
GLib/LLVM global storage remained. That is still all-kinds **NOT_PASS**. Its
memory log SHA-256 is
`cda411222f0171b9d0f1bd106ff6e6ec33c92c77704a253e2050bc2d4d21a24b`.
These are authenticated historical observations, not a new C0 memory test or
original-byte restoration.

The original C0 remains absent. The 1,044 lost original raw proof records remain
lost. Milestone 27-B remains PARTIAL. Replacement C0's recorded strict all-kinds
process-memory result remains **NOT_PASS** (reachable GLib/LLVM global storage);
this decision supplies no memory waiver or passing measurement. Applicable
release safety qualification or a separately explicit risk disposition remains
necessary wherever the release gate requires it.

The authorization changes provenance disposition only. It authorizes no C0
modification, semantic weakening, history rewrite, release publication or tag.
Contemporary native, self-hosting, O0/O2, ownership, ABI, safety, memory,
reproducibility and delivery checks still apply. Keep the proof-record loss and
memory status separately visible in the release exception ledger.

The owner's supplied interpretation is: “I give explicit release disposition
for rebuilt C0.” This record applies that permission to the rebuilt-C0
provenance substitution and carries it forward into milestone 28.
