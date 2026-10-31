# Declaration-driven foreign APIs

`profile="declarations-v1"` derives foreign methods, constructors, accessors and
signals from checked declarations. Mark the exported members with `[Foreign]`;
use `[ForeignChannel]` where the logical type needs explicit encoding, direction,
count, nullability or transfer facts. The legacy bounded profiles keep their
existing spellings and expectations. [ADR 0166](../decisions/0166-declaration-driven-foreign-apis.md)
records the approved contract.

```astra
namespace Demo;
[Shared]
[CExport(name="demo", profile="declarations-v1", bool_abi="c99")]
[GObjectExport(type="DemoService", namespace="Demo", version="1.0",
	profile="declarations-v1")]
class Service {
	private int count;
	[Foreign] init() { this.count = 0; }
	[Foreign] property int calls { get { return this.count; } }
	[Foreign] f64 adjust(i64 input, f64 bias, bool negate) {
		this.count = this.count + 1;
		f64 result = input as f64 + bias;
		if (negate) { return -result; }
		return result;
	}
}
```

Unique Classes remain unique. Their C owner has explicit consuming destruction;
adding an export does not add native reference counting. Shared Classes retain
one native strong/weak authority while C, COM and GObject views coexist. Foreign
wrapper identities are separate from native storage. Callers must obey each
owner/borrow duty and keep backed owners during calls.

## Channels and target layouts

| Channel | Supported contract |
| --- | --- |
| Scalars | bool, signed/unsigned 32/64-bit integers, f32/f64; exact widths and signedness retained. C bool requires explicit `bool_abi="c99"`; COM BOOL and GObject gboolean are 32-bit. |
| POD | Copied scalar records, nested scalar fields and exact closed generic records; target-specific C/COM/GObject layouts convert to independent native leaf groups. |
| Bytes and UTF-8 | Counted byte views, bounded output/inout with produced counts, independent owned byte results; counted UTF-8 preserves NUL, explicit NUL UTF-8 rejects unrepresentable embedded NUL output. |
| References | Borrowed i32/u32/i64/u64/f32/f64 input/output/inout places retain exact pointee and noescape facts. Unrestricted pointer reinterpretation is not an admitted channel. |
| Objects | Exact nominal borrowed, consumed and owned native Class or imported provider handles, nullable results and independently owned cross-root results. Source ownership and provider release operations remain authoritative. |
| Checked calls | Named domain/status mapping and exact throws bound, error factory for imports, zero/empty outputs on failure and staged publication after conversion/retirement. |
| Callbacks | Synchronous call-scoped typed code/context callbacks, including admitted native captured Closure views. Escaping a borrowed callback rejects. |
| Properties | Member-derived copied scalars/POD and owned text/bytes/object results, explicit checked accessors where supported; GObject properties include int/bool/double/text/object. |
| Signals | Synchronous selected native signals with scalar, boxed POD, bytes/text and object channels. Exported object arguments project to real GObject carriers. |

The normalized descriptors retain nominal member identity, ordered parameters,
effects and ownership independently of physical layouts. Core, CFG, SSA, native
ABI, CABI and LLVM validate their own bindings. Detached mutations check that a
physically plausible same-width substitution, reordered field, wrong native
member, changed cleanup, IID/slot or callback/context operation is rejected.
These checks validate declared contracts; they do not prove arbitrary foreign C
implements its promises.

COM interfaces derive slots and IIDs from actual interface members, including
multiple interfaces on one root. QueryInterface returns a canonical IUnknown;
each acquired interface has its own reference duty. Calls keep constructing-thread
affinity and initialize valid outputs before refusal. Qualification covers native
Windows x64 in-process use; activation, registration, inter-apartment marshaling,
method-state thread safety and cross-DLL native exception descriptors are outside
this evidence.

## Generation and imports

Generate verified headers with `--emit-class-header`, `--emit-com-header` or
`--emit-gobject-header`. Generate mechanical target glue with the corresponding
`--emit-class-source`, `--emit-com-source` or `--emit-gobject-source`. Compile the
native object with `-c`; link the explicit boundary providers required by the
selected surface. POD C forwarders are a separate generated object when linking
the COM surface. The recipes below show complete supported commands.

C imports use bodyless checked declarations with exact provider names, lifetime
and error factories. COM imports use bodyless interfaces with declared IID and
slot order. GObject imports retain exact carrier/GType and transfer facts.
Selected GIR declarations generate usable `bindings.astra`, VAPI, C header/source
and an exact contract receipt. Run `tools/gir/import.py --verify` against those
products before compilation. Omitted GIR parameter groups normalize to empty
inputs; duplicate groups, missing method receivers and malformed signal groups
still reject with XML coordinates. This is a selected strict profile, not a GTK
binding or arbitrary dynamic introspection engine.

The optional `gobject-signals-16.c` provider connects typed retained native Closures
for synchronous, nonthrowing void callbacks with zero through four copied scalar
parameters. Revoke disconnects; observe requires callback quiescence and GClosure
retirement before native capture destruction. Dispatch remains on the constructing
thread and recursive same-registration dispatch refuses. Retained native handlers
with object/text/record parameters remain outside this finite retained profile;
independent C/GI handlers can consume those exported signal channels. The older
`int(int)` retained provider remains compatible.

## Composition and reproduction

Use `--foreign-personalities=c,gobject`, `c,com` or `none` explicitly. One common
source carries all three declared policies; the target selects active surfaces.
Native-only products acquire no GLib/GObject/COM dependency. The `/4` opaque
[native-unit schemas](native-units.md) retain foreign declarations, native symbols,
layout, compiler identity and exact transitive object receipts without producer
implementation bodies, source fallback, bitcode or LTO.

Run the SDK recipes from the checkout with absolute compiler and external output
paths. They copy clients and install generated artifacts outside the source tree:

```sh
python3 tests/declaration-interop-16/api-a.py /absolute/astrac /external/output-a
python3 tests/declaration-interop-16/api-b2.py /absolute/astrac /external/output-b
python3 tests/declaration-interop-16/api-b3.py /absolute/astrac /external/output-c \
	/absolute/astra/docs/declaration-interop-16-api-a-freeze-3.json
```

Each compiles leaf → component → adapter/client at all eight O0/O2 combinations
plus O1, removes only task-owned producer source copies, checks imported file
access/symbols, and runs independent C, generated-SDK C, native, GObject C, GI
and GIR round-trip clients. Windows recipes `api-{a,b2,b3}-windows.py` accept explicit
`--compiler`, `--cc`, `--cxx`, `--sysroot` and `--output`; native Windows execution
is a separate required step. Their 27 exact binaries per API passed in the scoped
existing win11 session, including independently defined COM layouts and providers.
The VM remains running, its temporary CD is empty and persistent XML is unchanged.

API A implements checked byte transformation, snapshots and closed generic
statistics. API B2 implements record selection, nullable independent result owners,
metadata and distinct signals. The first API B challenge failed the original
freeze on a valid zero-argument GIR constructor. That failure remains recorded;
the generic fix, API A requalification and replacement freeze precede B2. Its
SDK challenge passed, but full integration found malformed-callee verifier ordering
and repeated recursive field-context lookup. The failed integration record remains
failed. After a general repair, fresh strict build and API A requalification,
freeze three precedes B3. The variants change namespace/type/version, member
names/order with new IIDs, POD order/extra fields, a new u64-returning method,
private helpers and source partition. B3 additionally substitutes a closed f32
record result, adds a float query input and changes the retained signal to f32.
A provider-only native behavior change preserves public declarations but changes
the independently expected foreign result. Frozen challenge credit requires the explicit freeze argument (or Windows
`--freeze`); ordinary default runs qualify the current compiler only.
A separate propertyless class checks
a substituted i64/f64/bool method signature.

Linux memory evidence includes unsuppressed whole-client Valgrind and ASan on
actual emitted native code, with UBSan on C boundary glue. System GLib/GObject is
uninstrumented. Windows evidence includes exact retirement observers and
HeapValidate, not Windows leak measurement. The retained runtime's narrow Helgrind
witness passes with one standard libc suppression; its unsuppressed thread-join
finding has a standalone GLib reproducer. This establishes the tested protocol,
not general race freedom.

The final qualification records
all 9,424 current passing registrations and the source-bound delivery ledger. Historical slice ledgers retain their original identities
and then-open obligations. This work does not release RC2 or establish unrestricted
Windows, GTK, foreign threading or Bible-complete status.
