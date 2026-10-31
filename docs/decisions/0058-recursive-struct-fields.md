# ADR 0058: Recursive native struct fields and aggregate Places

Status: accepted for ASTRA-STRUCT-AGG-1.
Baseline: `1fc89849dde493cbe74128a910a449729e92bf2b` (ASTRA-GEN-CAP-1).
The uncreated GEN-STRUCT-1 ADR 0058 proposal is superseded. GEN-STRUCT-1 remains
deferred and must use ADR 0059 when it resumes.

## Context

Native struct storage previously admitted integers, f32/f64, bool and void*.
Native structs and classes shared the same field predicate. StructType and
VectorType fields were rejected. Core/CFG FieldPlace already declared a Place
base, but canonicalization, verification, promotion and physical lowering assumed
that base was a local. These limitations also prevent future generic composition.

## Decision

1. Native structs may contain concrete native StructType fields and every
   already-supported VectorType shape, in addition to all previously accepted
   scalar/native fields. The shared NativeFieldTypes authority takes the owner
   category; class admissibility is unchanged. ClassType, handles, slices, arrays,
   typed pointer fields, owned/borrowed fields and other rejected categories are
   not admitted. void* and exact f32/f64 behavior remain unchanged.
2. A struct-valued field is a storage subobject and a Place. It is not automatically
   a whole-struct Value. One FieldPlace composes recursively over an exact Place
   base, including a LocalPlace, another FieldPlace, or a DereferencePlace.
   Existing indirect receiver roots continue to compose. Every projection retains
   the exact field identity, its exact owner StructType, result type and provenance.
   Semantic field names resolve upstream; downstream code never repairs a mismatch
   by looking up a name or concatenating a path string.
3. Leaf scalar/vector fields can be loaded as ordinary Values. Intermediate struct
   fields are never loaded just to access their children. There is no whole-struct
   load, copy, assignment, aggregate temporary, hidden memcpy, native by-value
   parameter/result, or C aggregate ABI. Such features require a separate decision.
4. Nested braces initialize the selected subobject directly. Checked initializers
   retain target type, exact field identities, child initializer or leaf expression,
   provenance and written order. Core retains nested direct-storage initializer
   statements. Completeness is recursive: unknown, duplicate and missing fields
   reject with the nested source path in diagnostics. All leaves must satisfy exact
   existing type rules. A struct field requires braces rather than an existing
   struct expression. No default, partial, or implicit zero initialization is added.
   Evaluation follows depth-first written initializer order, not declaration order.
   Declaration order remains authoritative for field ordinals and physical elements.
5. A vector field holds one whole VectorType value. Reading loads that whole value;
   writing stores that whole value. Lane reads extract a Value. Lane insertion
   returns a whole vector which can be assigned to the field. Lane writes do not
   create LanePlace semantics.
6. By-value StructType dependency graphs must be acyclic. Direct, mutual and longer
   recursion reject using exact StructSymbol identities in semantics and exact
   stage-owned descriptors in Core. Semantic checking follows complete field
   resolution and precedes bodies; Core independently verifies the graph. CFG and
   SSA also defend their standalone model boundaries. Forward references retain
   existing declaration collection rules. Pointer edges do not embed pointee
   storage, although typed pointer fields remain unsupported here. Vectors are leaves.
7. Physical sizes, offsets, padding and alignment belong to the backend/DataLayout,
   not semantic type identity. LLVM fields use ordinary nested concrete struct,
   existing vector, scalar and exact double types, in source declaration order.
   Neither a combined nor successive GEP form has semantic significance.
8. Existing local scalarization remains the default. A nested struct or vector
   alone never forces memory. Nested leaves promote independently through ordinary
   SSA definitions and block parameters, keyed by exact CFG Place identity. There
   is no whole Inner or Outer SSA value and no parallel aggregate promotion model.
9. Addressability remains local-wide. If a root local is made addressable, one
   concrete object backs that root and every recursive access derives physical
   addresses through the same Place routine. Other locals of the same type retain
   promotion eligibility. No per-subobject split storage is introduced.
10. Existing typed Struct* pointers, aliases and null trapping compose with nested
    fields through `p->inner.x`. No new pointer type, borrowing/exclusivity contract,
    Place category below FieldPlace, NABI type/profile, CABI/VAPI channel, runtime
    descriptor, typeinfo, heap allocation, ownership semantics or production
    dependency is introduced. Historical direct/indirect root forms remain within
    the existing storage architecture; there are no depth-specific Place classes.
11. Struct receiver methods and property accessors can access `this.inner.x` through
    the same recursive projection. Invoking methods/properties on nested substruct
    receivers, general expression receivers and taking subobject addresses remain
    deferred under the existing direct-local receiver/address rules.
12. No generic aggregate semantics or representation is introduced. Generic functions
    may use ordinary concrete nested structs. GEN-STRUCT-1 must reuse this machinery
    for concrete fields, initializers, projections, promotion and layout rejection,
    rather than create parallel generic field lowering. Generic application identity
    and cycle detection during generic instantiation remain future work.

## Consequences

One recursive storage model covers promoted and memory-backed leaves. Stage-owned
field/type descriptors and initialization trees outlive upstream syntax and
symbols without ownership cycles. SSA retains a transitive concrete descriptor
graph only for memory/receiver roots. Debug names and copied ordinal paths describe
promotion origins, but never key definitions or identify physical subobjects.
The accepted scalar-only dump formats remain stable; new nested forms make bases
and field identities explicit. Existing aggregate Value and ABI firewalls remain.

See [language](../language/nested-struct-fields.md),
[recursive Places](../ir/recursive-field-places.md), and
qualification.
