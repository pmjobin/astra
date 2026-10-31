# Independent native units

The compiler-pinned GNU x86-64 LP64 and Windows x64 LLP64 interface profiles
support separate Astra compiler invocations with native symbols, ownership and
layout checks. This complements
ordinary [multi-source namespaces](modules.md).

Compile a producer with explicit public selectors:

```sh
astrac -g -O2 -c --module Native8 --emit-interface /tmp/native8/provider.asti \
  --native-export Native8.Pair --native-export Native8.Cell \
  --native-export Native8.twice --native-export Native8.pack \
  --native-export Native8.adjust --native-export Native8.make \
  --native-export Native8.inspect \
  tests/ecosystem-abi-8/module-provider.astra -o /tmp/native8/provider.o
```

Create the destination directory first. Output object and interface must be
siblings. For repository qualification use the managed external build area,
not the illustrative `/tmp` path. Supply a normal C observer object defining
`module_event` when linking this fixture.

Compile a later consumer and link the existing producer object:

```sh
astrac -g -O0 --entry-object --import-module /tmp/native8/provider.asti \
  tests/ecosystem-abi-8/module-consumer.astra -o /tmp/native8/consumer.o
cc -no-pie /tmp/native8/consumer.o /tmp/native8/provider.o observer.o \
  -o /tmp/native8/program
```

`--entry-object` includes the real executable entry wrapper; ordinary `-c`
retains its prior meaning. Executable compilation with `--import-module` also
links the verified existing object automatically. The consumer reads the
canonical declaration model and existing object identity; the producer's
implementation source need not exist. Native imports become external fastcc
symbols, without model implementation bodies or a C proxy.

The `astra-native-module/2` format records the exact compiler binary, target,
native signatures/ownership, nominal types, private field visibility and actual
LLVM target sizes/alignment/offsets. Its symbols include an ABI identity. The
receipt additionally binds the declaration model and object SHA-256. An old
compiler, mismatched target, changed owned result, forged/stale object or
corrupted metadata fails before unsafe emission. Rebuild interfaces/objects
when rebuilding the compiler, or select the checked legacy path below for an
unchanged supported ABI. These local receipts do not authenticate an
untrusted author or supply a stable cross-version package ABI.

The GNU schema is now `gnu-x86_64-lp64-runtime-units/6`. It records the explicit
`runtime-contexts/1;tasks/17;endpoints/1;effects/1` contract in addition to each
exact transported channel. Allocator parameters/results and stored allocator
fields retain their nominal name, lifetime/thread mode and release symbol.
Selected Class allocation policies and task/provider/capture contracts remain
part of the checked signature/layout. This does not widen source lifetimes.

GNU `/6` adds a mandatory `astra-optimizer-summary/1` field for each callable.
It can describe absence of external memory effects and logical-formal capture/read
effects. It grants no `noalias`, nonnull, FP, lazy or concurrency permissions.
An importer first checks the exact typed signature and nominal layout, then checks
any claimed effect against the supplied ELF object's decoded native instructions.
Fingerprints alone do not prove effects. The current object checker admits a
conservative scalar instruction domain, scalar nominal fields and typed direct
calls, including bounded conditional direct tail calls after checked scalar tests.
Each taken edge checks its exact typed callee; fallthrough retains its original
register/stack state and is checked separately. Pointer predicates are admitted only
as explicit null-refusal paths with a terminal trap. Arbitrary branches and pointer
bit/identity tests remain closed. Local callees are independently checked in the same object; dependency
callees require their checked object receipts and exact nominal/signature identities.
Known null-refusal guards preserve their traps and never grant memory-none facts.
Unknown calls, atomics, pointer identity results and replaceable weak/COMDAT
bindings supply no authority. Unsupported valid
producer code exports unknown facts. False or unsupported imported claims refuse
before executable emission. Producer sources and serialized implementation bodies
are unavailable to this proof. GNU `/5` units require rebuilding. Existing legacy
and Windows restrictions remain unchanged. See the
approved contract.

Optional native proof state admits 128 exact private stack slots and 128 call
relocations per function, with at most 64 active call proofs. Cycles and larger
unproved cases export unknown summaries; accepted source remains usable. Every
claimed imported fact still requires the admitted proof. These bounds constrain
optional optimization work rather than introducing a new source refusal. The
register model follows the qualified
[LLVM 22.1.8 x86 calling-convention definitions](https://github.com/llvm/llvm-project/blob/llvmorg-22.1.8/llvm/lib/Target/X86/X86CallingConv.td).

Each GNU `/6` callable also carries a canonical `runtime-lifetime-logical/1`
archive of its lifetime summary. Summary `/1` describes ordinary/deferred channels;
summary `/2` adds a synchronous checked exception channel. It preserves independent allocation roots,
owned field/element paths, exact formal context anchors, receiver updates and
stored-input effects using sealed integer equations. The payload is included in
the existing ABI digest and exported symbol identity. A changed payload cannot
reuse the original object under a resealed interface. Imports check the codec,
signature input roles and immutable declaration in Source, Core, CFG and SSA;
native planning copies and rechecks the actual SSA summary without retaining SSA.
Unknown effects carry an explicit incomplete marker and provide no scoped-owner
authority. The wire limits are 65,536 equations and 8 MiB per summary, within the
existing total interface limit. Legacy and Windows metadata remain unchanged.
The consumer now also binds these effects to the exact external LLVM declarations.
Supported scoped factories and constructors retain their original context debt;
eligible direct mutators retire old fields and publish their exact replacements.
Opaque cold tasks preserve scoped captures through observed success, error,
cancellation or discard. Qualified scalar/owning-record success and scoped exception
paths include ordinary await and a catch retained across another suspension.
Imported exception descriptors retain exact nominal parent/destructor roles while
their producer initializers remain opaque. The producer bodies must pass their own
emitted lifetime proofs. These contracts grant no worker transfer to affine owners.
See [allocator contexts](allocator-contexts.md) for supported field/outcome shapes
including same-nominal empty/filled exception roots with proved null initialization
and subsequent ownership-preserving field replacement.

The public `opaque-scoped-tasks.py`, `opaque-scoped-errors.py` and
`mutable-scoped-field-units.py` and `same-nominal-error-units.py` recipes exercise
genuinely separate units, mixed
O0/O2 and O1, hidden producer source, metadata refusals and generated-product safety
tools. A complete native producer command also accepts `--dump-llvm`: it prints
the normal module IR to stdout without writing the validated object/interface
destinations, allowing instrumentation of the actual producer.

Owned `ContextBytes<AllocatorType>` results, borrowed parameters and Class/record
fields use an exact `CONTEXT-BYTES` descriptor in GNU `/6`. It retains the nominal
allocator type, thread mode and origin-release symbol alongside the physical
pointer/length channels. Opaque consumers cannot reinterpret it as an ordinary
owned byte buffer or another allocator mode. Such transport requires the current
GNU schema; legacy and Windows profiles refuse it.

The GNU `/6` and Windows `windows-x64-llp64-foreign-units/4` profiles retain
exact scalar/record, ownership, callable, checked-effect and native task contracts.
They additionally retain selected C/COM/GObject declarations,
resolved member/channel identities and public bridge symbols. Exact native Classes
carry their fields, explicit init/deinit, methods, properties and heap/borrow origins. Records may nest other exported records and own
exported exact Classes or primitive buffers. Their complete leaf/cleanup plan
and move/copy mode accompany the physical ABI and target layout. Every nominal
dependency must have its own explicit selector.

A producer may import compiled producers. Each direct dependency records its
module name, adjacent interface basename, complete interface SHA-256, object
SHA-256 and ABI identity. A later consumer imports the middle interface alone;
the compiler loads its declared dependencies in deterministic dependency order
and links each exact nominal module once. Diamond branches must agree on the
complete interface/object origin. There is no source-tree or current-directory
fallback. Stage all graph interfaces and objects beside the producer interface
before compiling a dependent producer; artifact trees can then be relocated.

`--import-legacy-module FILE` explicitly checks unchanged GNU `/3` or `/4`
artifacts from an older compiler. It retains canonical metadata, object hashes,
symbol, target, declaration, ownership, layout and effect validation; it does
not reinterpret opaque task frames. Legacy task metadata and allocator-context
transport require rebuilding with `/6`. A newly compiled `/6` producer records
an accepted legacy dependency as `legacy-unchanged/1`; its consumers recheck that
dependency automatically. Ordinary `--import-module` retains the current exact
schema/compiler requirement. A `/6` dependency may omit its redundant
`compatibility=runtime/5` policy marker; this retained marker name does not name
the enclosing interface schema. Omission retains those strict current checks.
It never selects the legacy path. Unknown marker values reject, and the emitter
always writes an explicit marker. The exact serialized field inventory remains
part of the ABI/interface digests and exported symbol identity.
Windows allocator-context native transport remains
outside the qualified schema and is refused; ordinary Windows `/4` stays as before.

The resolver rejects cycles, conflicting module origins, symlinked artifacts,
unsafe basenames, missing/stale objects and mismatched dependency facts before
native emission. It admits at most 256 distinct native units (including the
producer), 65,792 interface paths, 65,536 dependency edges, 64 edges of depth and
32 MiB of interface data per invocation. Each interface carries at most 4,096
callables and 1,024 nominal types. Each interface
is limited to 2 MiB and each object to 128 MiB. Reads enforce the file size limit
before allocating its contents. These are deterministic resource bounds, separate
from source generic type rules. Unsupported old format/schema artifacts require a rebuild.
The [transitive graph driver](../../tests/structural-generics-15/units.py) exercises
L→M→C, diamonds, relocation, absent implementation sources and metadata mutations.

Record ownership is derived normally; an owning record argument requires an
explicit move, and returned values retain their complete cleanup plan. A later
consumer can construct the same record, move out selected fields and call the
producer's imported Class destructor. The declaration witness bodies are checked
but never emitted as local import implementations. Checked record shapes retain
their own finite structural bounds. The [public owning-record unit fixture](../../tests/language-generalization-10/unit-record.py)
demonstrates separate processes, absent producer source, O0/O2 linkage and memory
checks.

Closed general generic Classes over exported records have explicit selectors:

```sh
--native-export 'Composite10.Store<Composite10.Envelope>'
--native-export 'Composite10.Store<Composite10.Sample>'
```

Also export each argument and its nominal dependencies. Closed generic records
and Classes retain their actual ordered type arguments,
field graphs and exact selected member signatures. Each selected Class
specialization exports its methods and derived destructor. Its
owning factories/parameters have the existing fixed heap contract. The interface
describes checked declarations, so producer algorithms and implementation source
remain unnecessary to consumers. Instantiating an unselected specialization in
a consumer is refused at the native boundary before emission. Raw early-stage
dumps precede that boundary. See the
[generic unit witness](../../tests/language-generalization-10/unit-record.py)
and [decision](../decisions/0155-closed-generic-native-unit-specializations.md).

Exports must belong to the named namespace. `internal` exports and private field
access reject. Export exact closed generic instances and their nominal dependencies;
open generic exports and unsupported virtual/property specializations reject.
Checked methods carry their exact exception bound/root and private success shape.
Native Class/Resource borrow and owner channels retain their exact origin and
cleanup contract. Borrowed slices/text, copied Fn values and bounded synchronous
Closure/Callback channels carry their physical signatures. A declaration-driven
foreign member may additionally return an owned byte/count pair. Native-unit
metadata does not widen an unsupported source lifetime or foreign ABI channel.

The current profiles preserve declaration-only imported C Classes, COM interfaces and
GObject Classes with exact factory, nominal, selection and lifetime identities.
Selected exports can expose owned object properties and copied checked properties;
scalar references retain an explicit borrowed scalar pointee. Lazy caches and
custom allocator code exports remain outside this native-unit profile. Imported
producer implementations are never reconstructed from method bodies or source.

Use explicit `--foreign-personalities=c,gobject` on GNU/Linux,
`--foreign-personalities=c,com` on Windows, or `none` for the native-only product.
The same common source declarations are qualified in both foreign combinations.
An explicitly selected incompatible target rejects. Windows native units are
qualified within one linked image; native exception descriptor sharing across
independently linked DLLs is outside the qualified domain.

See the [declaration-driven interop guide](declaration-driven-interop.md),
[opaque foreign channel recipe](../../tests/declaration-interop-16/opaque-channels.py),
[API A SDK](../../tests/declaration-interop-16/api-a.py) and
[replacement frozen API B3 SDK](../../tests/declaration-interop-16/api-b3.py).
The older schema-1 profile remains recorded in ADR 0131; rebuild artifacts with
the current compiler and schema.

See [ADR 0131](../decisions/0131-versioned-independent-native-units.md), the
[module qualification recipe](../../tests/ecosystem-abi-8/module-check.py) and
[A61–A64](../../examples/ecosystem-abi-8/README.md).
The [owning record decision](../decisions/0154-owning-record-native-unit-boundaries.md)
records the extended lifetime correspondence and its current limits.

The M17 [context SDK recipe](../../tests/runtime-composition-17/context-units.py)
builds two opaque libraries and a consumer in all eight O0/O2 combinations plus
O1. Its copied SDK has no producer source and is consumed outside the checkout.
The [legacy recipe](../../tests/runtime-composition-17/legacy-units.py) takes an
explicit preserved M16 SDK directory, verifies and copies its original artifacts,
then executes unchanged `/4` objects with current consumers and a new `/6` wrapper.
