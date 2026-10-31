# Owning record boundaries in independent native units

The explicitly selected GNU x86-64 LP64 native-unit schema is now
`gnu-x86_64-lp64-composite-owners/2`, within the existing
`astra-native-module/1` container format. The exact compiler/object/target
fingerprints and ABI-derived exported symbols remain mandatory. Original
schema-1 receipts remain historical; this does not establish cross-version or
external C ABI stability.

Selected nongeneric records may contain nested selected records, owned exact
native Classes and owned primitive buffers. Record methods, foreign Resources,
virtual/interface/throwing/async exports and transitive producer imports remain
excluded. Native Classes keep the existing scalar-field, explicit init/deinit
profile. Every nominal dependency must be explicitly exported; internal types
and private field access retain ordinary source refusal.

The generated declaration model contains type fields and typed witness bodies,
never producer implementations. An owning record result witness initializes
fresh child-Class and buffer owners, constructs nested values and returns by
move. Its normal Source/Core/CFG/SSA ownership checks derive the same transport
contract as the producer. These bodies are discarded at LLVM import emission;
the consumer calls only the verified producer symbols. Default initializers
have a finite nesting bound of 32. Consumers do not require producer source.

Native signature correspondence now includes record copy/move mode, nominal
name, result carrier, every physical leaf's source/storage path and buffer
component, and every cleanup's exact nominal Class or buffer element/base/length
channels. Type layout receipts also preserve field ownership with target size,
alignment, offsets and private visibility. Whole-record arguments use their
independently checked complete boundary groups; a pointer-width match cannot
convert one of these leaves into an unrelated ordinary parameter.

Direct nongeneric Class owner parameters remain outside this finite unit
profile: their existing in-program allocation-origin inference can choose a
different domain when a separate caller appears. The first prototype exposed
that mismatch. Whole owning-record fields already have fixed heap responsibility
and are transported under the established G1 value plans. General container
owner inputs also have fixed heap origin, but their exported specialization
surface still needs its separate G7 implementation. No default Class-origin or
unique ownership semantics are changed to hide the distinction.

The public witness separately compiles producers at O0/O1/O2, removes only its
task-generated producer source, then compiles consumers and invokes the C linker
in independent processes. The five O0/O2 mixed and O1 paired combinations execute
whole-record creation, forwarding, consumption, caller construction, bounded
field extraction and imported Class destruction. Exact computed outputs and
destructor order match under unsuppressed Valgrind. Public controls reject
copy/moved/private misuse and wrong schema, target, layout or ownership receipts.
An independent plan proof bypasses receipt hashing and rejects record move-to-copy
and same-width buffer cleanup substitutions, restoring each before LLVM checks
after predecessor release. Earlier scalar/POD/Class module and LLVM linkage
controls remain selected.

This qualifies the owning-record part of G7. Closed general generic exports,
the integrated A82 program and final campaign qualification remain outstanding.
