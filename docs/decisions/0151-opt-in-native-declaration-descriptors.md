# Opt-in native declaration descriptors

Native metadata is an explicit generated-source facility. The driver snapshots
selected checked native declarations, releases its semantic graph normally, and
writes ordinary Astra source only after the original program passes Core, CFG
liveness, SSA, native and LLVM verification. A normal compilation has no registry,
extra Class header, dynamic type test or reflection dependency.

`--emit-native-descriptors --descriptor-module Witness --describe Type -o file`
selects 1..32 nongeneric native Classes, records or interfaces. A qualified type
may use `Alias=Namespace.Type`; aliases and the module are bounded identifiers.
The output namespace is `NativeMetadata_Witness`. It must be absent from the
input declarations. Private fields and synthetic lazy factory/lifecycle members
are excluded. Declared fields, properties and ordinary methods are ordered by
their original source position. Inherited inventories and generic declarations
are outside this first profile.

Type and member descriptors are copied records, describing a declared nominal
view. Version 1 carries a positive 31-bit FNV-1a module tag and a nominal ID over
the module, kind and qualified type name. Selection order and input-file order
do not change the output. Duplicate selections and actual nominal hash
collisions reject generation; hashes are identifiers, not authentication.
This is not a persistent schema or a stable binary ABI. Regenerate metadata
with the declarations it describes; changing a declaration can change member
ordinals without changing its nominal type ID.

Queries validate module, version, selected ID and member range. Unknown or
forged invalid records throw a checked Error. A valid copied descriptor grants
no storage authority. Generated readers accept an ordinary typed receiver and
return a copied int field/property, or invoke an int-returning method with zero
or one ordinary int argument. They check receiver descriptor identity and null
references before access. Interface calls keep ordinary dynamic dispatch.
Owning records have descriptive metadata but no copied-record reader. No raw
offset, erased pointer, mutable view, owner extraction or arbitrary dynamic cast
is exposed. All generated accesses undergo the normal public compiler pipeline.

The explicitly selected standard Error root supplies recoverable failures.
Generated readers propagate ordinary checked getter/method failures. Existing
nominal privacy, ownership, borrowing and lifetime rules remain authoritative;
metadata cannot manufacture a receiver or keep it alive. Source-free snapshot
tests release the original Class/record graph before rechecking generated text
against newly constructed nominal declarations. Public tests execute typed
inspection, dynamic dispatch and forged-record errors at O0/O1/O2 with
unsuppressed Valgrind, including qualified aliases, a real hash collision and
failure before artifact publication. A peer compiled from the same model
without the generated source lacks the selected registry names, query errors
and heavy runtime dependencies.

See the [source guide](../language/native-descriptors.md) and
[public evidence recipe](../../tools/qualification/language-generalization-10.md).
