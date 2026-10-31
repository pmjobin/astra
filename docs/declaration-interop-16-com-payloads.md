# M16 typed COM payload and export integration

The declarations-v1 COM projection now carries mixed scalar PODs, counted byte
input and bounded output, owned byte/count UTF-8 results, scalar references,
synchronous callbacks and typed imported interface owners. These are mechanical
transport conversions around declared virtual calls or compiled native methods.
The existing bounded Value/Scale profile remains separate.

`ForeignComRecordLayout` computes Windows scalar storage independently of native
and C99 storage. Its BOOL fields occupy four bytes. Generated records assert size,
alignment and every field offset; conversion copies each scalar field and normalizes
booleans. The independent Windows client/provider defines a 48-byte mixed record
with adjacent BOOL fields, 64-bit integer/FP fields and independently asserted offsets.
No native Class or compiler-private record layout is used as COM storage.

Owned imported byte/text results use the COM task allocator. The private C bridge
has an exact matching release operation; the native caller stages and validates
counts, UTF-8 and produced extents before publishing. Provider errors release
provisional owned results. A test-only shim observes each matching free and then
calls the real SDK function; it does not replace the allocator. Each tested import
process allocated six result buffers and freed each once, including failed and
malformed results. This is an allocation-specific balance check, not a claim about
all Windows allocations. See Microsoft's [CoTaskMemFree contract](https://learn.microsoft.com/en-us/windows/win32/api/combaseapi/nf-combaseapi-cotaskmemfree).

`[COMExport(interfaces="IQuery,IDetail,ITyped", threading="constructing",
profile="declarations-v1")]` on a selected plain Shared Class resolves each
requirement's `Foreign(native="...")` mapping to an admitted native member.
The immutable policy retains full protocol identities and exact target ordinals.
A nonthrowing native member may satisfy a checked interface requirement; a throwing
implementation must match its declared error bound and mapping. Property mappings
resolve actual getter/setter kinds. Missing members, mismatched channels and unique
roots reject before SDK emission.

The export wrapper inherits the selected interface leaves and exposes their declared
base views. Queries share one canonical IUnknown and one authoritative native root.
The wrapper uses the native root's existing synchronous personality cache, with no
second strong ownership cycle. Every dispatch checks constructing context and pins
the root until result publication. Owned byte/text outputs are independent COM task
allocations. Caller output buffers remain staged until all fallible conversions
succeed. C and COM views call the same compiled native operations and observe the
same state.

Actual Windows executions cover all four native/bridge O0/O2 combinations plus O1
in each direction. Independent prototypes test BOOL32 callbacks, inherited and
separate views, mixed records, embedded NUL in counted UTF-8, null/absent interface
errors, named checked failures, invalid counts, no publication after failure,
wrong-thread refusal, canonical identity, balanced references and single retirement.
A callback releases the last external COM reference during dispatch; the native
root remains alive until the call finishes. The independent interface relay borrows a real separately implemented provider,
executes its property through native Astra, and transfers that provider through a
native owned result with balanced foreign references. Import carrier retirement
is deferred while active synchronous borrows hold it; a direct callback releases
its owner and performs a nested typed call before the last active borrow retires.
The counter protects the private context carrier; actual IUnknown references
continue to own the foreign payload.

This remains intermediate M16 integration. [Native Class-valued interface projections](declaration-interop-16-com-native-roots.md)
are qualified by their subsequent pinned slice. GObject/GIR and retained signals, target selection,
foreign metadata in opaque native units, frozen distinct API qualification, exported
SDK reconstruction, final compiler qualification and the complete hosted registry
remain required. No G0–G9 completion or new release candidate is claimed here.
