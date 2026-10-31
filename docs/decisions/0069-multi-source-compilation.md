# ADR 0069: Multi-source compilation

Status: accepted for ASTRA-SOURCES-1.

## Context

Astra applications need ordinary source organization without prototypes, textual
includes or generated glue. The accepted PARAM-BORROW-1 compiler already collects
nominal types and callable signatures before checking bodies. SourceSpan owns an
exact SourceFile and original byte offsets; downstream stages own independent
symbols while retaining diagnostic provenance.

## Decision

One invocation accepts one or more source paths. Every native source contributes
to one global declaration universe, CheckedProgram, CoreProgram, CFG/SSA program,
NABI/CABI program and LLVM module. There is one ordinary final output. Files and
directories introduce no namespace, visibility boundary or initialization order.

`SourceSet` owns canonical ordered SourceFile objects. `SyntaxProgram` owns an
array of independently parsed CompilationUnitSyntax trees and views of their
original declarations. One Parser still reads one SourceFile. No source strings,
tokens, file spans or syntax trees are fused into a fictitious physical file.
The one-unit syntax dump and existing single-unit analyzer API remain compatible.

Names normalize redundant separators and `.` components. Relative paths stay
relative; absolute paths stay absolute. Case and `..` remain unchanged. No realpath,
symlink or inode lookup defines identity. Identical normalized input names reject
before file I/O. Different spellings that lexical normalization cannot equate are
distinct input units and remain subject to ordinary global declaration conflicts.

Canonical ordering uses normalized path bytes, independent of locale or CLI
order. Existing stage-specific declaration categories remain in their established
order (for example generic types, nominal structs, classes, and callable kinds).
Within each category, source path and declaration byte order determine traversal.
Keeping these queues preserves all accepted single-file ordinals and dumps.
Canonical ordering controls diagnostics and emission, never execution semantics.

All nominal names precede field resolution; every callable signature precedes
body checking. Duplicate names use the existing namespace rules. Cross-file
duplicates retain the existing primary message and add the previous path, line
and column. Same-file diagnostic text remains unchanged.

## Alternatives and consequences

Text concatenation would invalidate source spans and is excluded. Per-file
semantic programs or LLVM modules would require linking and new identity rules;
these are also excluded. A composition layer above the existing parser and
collector is sufficient, with no backend source orchestration or new dependency.
Flattened declaration arrays are references to original nodes, not copied text.

SourceFile object identity is compilation-local provenance. Paths are neither
semantic types nor generic keys, ABI channels or symbol-lookup authorities after
checking. Existing exact generic keys canonicalize instances across all sources.
File boundaries preserve ownership, borrow, struct-copy, object storage and
cleanup contracts. They introduce no runtime state, registry or initializer.

SyntaxProgram/SourceSet/parse trees can die after semantic analysis. SourceFiles
remain owned by retained spans under the existing lifetime policy, including
byte storage needed by span text and Unicode line/column computation. They own no
syntax trees. Core and later models independently verify after predecessor
destruction; the LLVM artifact owns no source graph.

Qualification found a pre-existing Core generic-cloner bug when a program combines
concrete buffer borrowing with generic ownership. Buffer borrow cloning used the
caller's local parameter map for a callee parameter. The bounded correction uses
the already-selected callee boundary, matching Resource and field-borrow cloning.
It adds no ownership semantics and changes no accepted baseline golden.

Modules/imports/packages, file-private visibility, partial types, extension
methods, overloads, separate compilation, stable module ABI, incremental caches,
project manifests, debug-info expansion, global initialization, const and a
standard-library framework remain deferred.

See [source model](../architecture/source-program.md),
[language](../language/source-files.md), and qualification.
