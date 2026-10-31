# Declaration-derived C POD records

The `declarations-v1` profile accepts copied records with public scalar fields from
the required scalar domain, including mixed integer/FP fields and C99 bool.
Closed generic record applications retain their exact nominal arguments.
Class implementation fields stay opaque. Owning/nested records and union active
projections are not reinterpreted as this scalar POD surface.

The checked descriptor records original field names, scalar kinds and order.
Core reconstructs those facts from its own ordinary or generic field declarations.
CFG/SSA reconstruct logical parameters from actual copied record leaf groups;
matching register widths cannot substitute another nominal record. Native plans
copy the admitted field declaration once and verify every scalar leaf, path,
group, nominal application and result independently. C ABI validation rechecks
the actual source/native member correspondence.

`--emit-class-header` emits C structs with deterministic type identities and
hygienic field names, plus C11/C++17 size/alignment/offset assertions. Foreign
storage is a separate natural scalar layout. LLVM checks every field against
the selected target data layout, initializes complete output storage including
padding, and loads/stores exact typed fields. Scalar POD output pointers must be
valid before native execution; failures leave defined zero output fields.

For record-bearing members, also compile the C11 output of `--emit-class-source`
with the target C compiler. It defines only typed forwarding functions: a copied
record argument is passed by address to the compiler-private bridge, which calls
the actual compiled Astra constructor/method/accessor. Public record inputs stay
ordinary by-value C arguments. This delegates register/stack classification to
the target C toolchain and supports adjacent fields without treating every field
as a separate C argument. No native application algorithm is generated as C.

The public and private symbols are claimed independently in the C ABI inventory.
The native object defines the bridge; the C forwarding object defines the public
record functions and references the bridge. Scalar-only members and lifetime
functions remain in the native object. SDK recipes must link both objects for
record-bearing APIs. Forwarder and native optimization levels may differ.

Windows aggregate conventions differ from GNU Linux, as described by
[Microsoft's x64 calling convention](https://learn.microsoft.com/en-us/cpp/build/x64-calling-convention?view=msvc-170).
Current new-profile execution evidence is GNU Linux x64. Extending the existing
Windows source/physical admission and running these channels on the authorized
guest remain mandatory M16 work.

The record integration uses independently defined Clang C records, GCC forwarding
objects, generated-header clients, and GCC/Clang C++ header layout oracles. It
executes actual native algorithms for a mixed 40-byte record, adjacent 32-bit
fields, a closed generic mixed record and a single-field record. The matrix
covers unique/shared O0/O1/O2, every O0/O2 native/forwarder pairing, and eight
whole-executable Valgrind runs. This is mechanism qualification before the full
opaque SDK challenge and compiler freeze.
