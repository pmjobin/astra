# ADR 0135: complete buffer field pairs in owning record locals

Status: implemented component of unfinished Surge 10.

An owned runtime-array field is a complete PTR/I32 owner pair with static
element layout and deallocation authority. It is not a scalar pointer leaf.
Record roots retain their separate Core/CFG responsibility from ADR 0134, and
the shared recursive path walk from ADR 0133 identifies each buffer field.

Core and CFG reuse ordered leaf acquisition and checked prefix rollback. SSA
expands each buffer field into an independent buffer storage slot with the root
source ordinal, full ordinal path and acquisition rank. Read/write places
snapshot that path and rank. Whole-record moves capture the complete pair,
disarm both source components and initialize the matching destination. The
existing buffer pair and memory-flow verifiers prove unique consumption and
cleanup; record checks additionally prove complete leaf coverage and matching
move paths. Buffer leaves do not acquire scalar heap-owner events.

The independent native plan carries complete element storage and PTR/I32
responsibility separately from Resource cleanup symbols and heap Class
ordinals. Primitive/vector and eligible copyable record buffer elements retain
their existing layout rules. Native local obligation metadata introduces no
new aggregate calling convention or C/GObject ABI.

Validation: nine aggregate TAP proofs cover metadata and physical corruptions,
including changed free operands after all upstream graphs are released. Four
public programs run at O0/O1/O2 with exact independent traces and unsuppressed
Valgrind. Each checked failure prefix, Class/Resource/buffer mixture, buffer-only
record, record-element buffer, zero extent, incoming/whole move and loop exit
has a real executable witness. Copying, persistent field aliases, reused incoming
owners and duplicate incoming moves remain rejected.

This component remains synchronous and nongeneric. It does not add partial take
or replacement, aggregate parameter/result transport, owning enum payloads,
generic containers or async record owners. G1 and the full Surge 10 milestone
remain open until those compositions have their required evidence.
