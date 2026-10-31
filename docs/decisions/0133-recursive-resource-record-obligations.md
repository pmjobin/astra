# ADR 0133: recursive Resource record local obligations

Status: implemented component of unfinished Surge 10.

Nested owning records reuse the existing lexical owner and cleanup scope. Each
Resource leaf has the exact root local, an immutable ordinal path, its nominal
type and cleanup identity, and its written acquisition rank. Declaration paths
do not determine retirement order. Repeated instances of one nested record type
have different paths even when their terminal field descriptor is shared.

Core verifies complete nested initialization and a unique obligation for every
owning storage leaf. CFG reconstructs canonical projections and proves the
initialized/live/moved/retired state of every leaf across normal and exceptional
edges. A checked producer fails before publishing the field's obligation.
Rollback retires the acquired prefix in reverse written order.

SSA promotes physical scalar leaves while retaining ownership events with path
snapshots. Whole-record moves transfer each leaf and disarm the source fields;
no aggregate pointer cast is introduced. The source-free native plan separately
copies declaration paths and local obligations as ordinal arrays, type names,
cleanup symbols and ranks. Its verifier rejects missing, duplicate, truncated
or mismatched paths without the SSA graph. Existing LLVM cleanup audits remain
responsible for the physical call operands after all earlier graphs are freed.

The component permits synchronous nongeneric nested Resource record locals,
scalar/vector companions and whole-local moves. It does not add aggregate ABI
transport, field extraction/replacement, owning Class/buffer leaves, owning
enum records or async owners. Those require their own ownership channels and
acceptance evidence. Copyability remains derived recursively; ordinary record
copy boundaries still require their existing copyability proof.

Validation: `language-generalization-10-aggregate-contracts` has five independent
corruption/restoration proofs. `language-generalization-10-aggregate` executes
exact cleanup traces at O0/O1/O2 and under unsuppressed Valgrind, including all
construction-failure prefixes and return/loop exits. The qualification recipe
also retains historical flat ownership and copied iteration controls.
