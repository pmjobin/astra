# Closed generic specializations in independent native units

The composite native-unit schema accepts explicit selectors such as
`Composite10.Store<Composite10.Envelope>`. The argument must be an explicitly
exported nongeneric copied or owning record. The template follows the established
general-body one-owned-slot Class contract; its ordinary methods and derived
slot destructor become the selected specialization's external native callables.
Open exports, Class/Resource/nested-container arguments, method type parameters,
properties, inheritance and checked/async template members remain outside this
finite unit profile. Domestic general generic support is unchanged.

The interface contains the template's fields and signatures with independent
typed witness bodies, never producer algorithms. Constructor witnesses create
the exact slot field; T-returning methods use its checked take operation; copied
primitive results use ordinary default values. Owning record arguments/results
retain the G1 move/cleanup plans. All model bodies pass the normal compiler
pipeline and are omitted when lowering imports to external declarations.

Each explicit closed selector also creates an internal record declaration
witness containing that exact owner. A separately parsed witness unit joins the
producer's original syntax before checking, and the same witness appears in the
interface. This requests materialization even when only a type is exported or a
consumer never uses it. It changes no user file, runtime Class header, registry
or allocation policy. These declarations have no executable initialization.
Unselected consumer specializations produce unregistered imported callables and
are rejected at the native boundary before a product is emitted. Earlier raw IR
dumps precede that boundary and are not its acceptance check.

Native callable fingerprints now include closed receiver/parameter/result
definition identity, field name, method result/parameter roles and ownership,
plus the complete record argument's nominal leaf/cleanup schema. Class layout
receipts include the same generic schema, physical slot offset, field ownership
and nonnull/visibility flags. Source-only numeric ordinals are not serialized as
cross-unit identities. Automatic constructor/destructor keys use their callable
kind, preserving the canonical `init`/`deinit` identity without relying on an
automatically generated function's source token.

The interface still requires the exact compiler binary, target/data layout,
versioned schema and matching producer object. The producer enforces the same
128-callable/64-type inventory limits as the loader. Selectors are bounded to
512 characters and one explicitly closed record argument; no erased T carrier or
implicit generic instantiation authority crosses the boundary.

The public witness exports copied and owning record specializations of the same
template. One specialization is materialized solely by its selector in the
producer, then constructed by the consumer. Real separate compiler/linker
processes exchange owning container factories and parameters, grow and replace
contents, return record values and observe exact cleanup at mixed O0/O2 and
paired O1. Generated producer source copies are absent during consumer builds.
Source/type/owner errors, unselected instantiations and wrong selector domains
reject. An independent correspondence proof substitutes a same-name generic
argument's move mode before receipt hashing, restores it, and verifies native
and LLVM artifacts after predecessor release. Public metadata fingerprints are
independent of selector/input ordering and optimization level.

This completes the selected G7 language components together with
[owning records](0154-owning-record-native-unit-boundaries.md). The integrated
A82 application and final same-revision G1–G9 qualification remain mandatory.
