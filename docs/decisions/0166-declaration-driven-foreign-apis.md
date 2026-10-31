# 0166 — Declaration-driven foreign APIs

Status: **approved by the user in the M16 native Codex interaction**.
The user approved the proposal at `81bb3ad0` and separately authorized the scoped
win11 testing described below. No historical fixture replacements were approved.
M16's G0–G9 remain the
finish line. The starting revision is
`4771575ecdb77191821292669744265c703c3a11`; the live baseline and host
authority are recorded in the checkpoint.

## Decision requested

Approve one normalized foreign declaration model with distinct C, Windows COM
and Linux GObject physical plans; an explicit `declarations-v1` opt-in; unique
C owners and one native lifetime for shared views; checked status/out boundaries;
typed synchronous callbacks and bounded synchronous native signals; declaration-only
adapter generation from opaque native libraries; and explicit target personality
selection. Implementation and all final qualification follow that decision.

Existing policy spellings retain their accepted bounded behavior. No historical
test expectation replacement is proposed in this decision. Any necessary later
replacement must identify an exact path/case batch and receive separate consent.

## Surface and member selection

The new Class export form is
`[CExport(name="session", profile="declarations-v1", bool_abi="c99")]`.
The `bool_abi` key is required when the selected C surface uses bool. The existing
`property="value"` form continues to mean the legacy bounded profile; mixing
that selector with `declarations-v1` is an error. Private fields never become ABI.

An explicit `[Foreign(name="...")]` selects a constructor, method or property.
It defaults to every selected personality that can represent that member;
`personalities="c,gobject"` can explicitly restrict selection. Foreign names are
portable and unique within their appropriate namespace. Ordinary source names,
arity, types, source ownership, accessor availability and checked errors determine
the operation. Unmarked helpers stay native. A Class may have no properties,
different constructor parameters, independent fields, and read-only properties.

`[ForeignChannel(parameter="input", ...)]` on a callable supplies transport facts
that its native type alone cannot determine. `parameter="result"` selects the
return channel. Keys are `direction` (`in`, `out`, `inout`), `transfer` (`none`,
`full`), `nullable` (`true`, `false`), `encoding` (`bytes`, `utf8-counted`,
`utf8-nul`), `length`, `capacity`, `produced`, `scope` (`call`), `closure`, and
`destroy`. Name references resolve to actual parameters, never magic positions.
Scalar and nominal types remain the checked source types. Redundant ownership
annotations must agree with source `owned`/`borrowed`; they cannot grant an escape
or forge an acquisition. Required absent, ambiguous, cyclic or contradictory
facts reject before code generation. String/array native counts are checked
against their source representation before conversion.

An interface with
`[COMImport(name="query", iid="...", threading="constructing", profile="declarations-v1")]`
contains actual typed requirements instead of `view="value|scale"`. Its members
also define an export protocol. A shared Class selects
`[COMExport(interfaces="IQuery,IMetadata", threading="constructing", profile="declarations-v1")]`.
Each requirement binds once to an exact checked native member with matching
signature/effects. Matching source names are the default; `[Foreign(native="...")]`
on a requirement makes an alternative binding explicit. This is a foreign view
mapping; it does not require multiple native inheritance or change native layout.
Imports receive nominal foreign interface owners and ordinary generated member
calls. Export and import use the same member/channel descriptors.

`[CImport(name="...", profile="declarations-v1", ...)]` on a declaration-only
Class describes the matching C factory/member/cleanup surface. Its selected
members have declarations, not implementation bodies. Unique/shared policy,
constructor symbols, owner destruction and optional acquisition/weak operations
are explicit, verified contracts. A method import cannot masquerade as a free
function by relying only on a pointer's width. Existing free C imports/exports
retain their current ABI; new Class channels use the new explicit profile.

`[GObjectExport(type="SdkService", namespace="Sdk", version="2.0", profile="declarations-v1")]`
uses the same selected members, with independently checked type/prefix/version
identities. Namespace versions are nonempty numeric `major.minor`, not universally
`1.0`. Ordinary properties map from actual accessor declarations. An incompatible
member selection produces a diagnostic; emission cannot silently drop it.

## Normalized model and independent checks

Build immutable descriptors after checking declarations. Each records exact
nominal origin/closed type arguments; resolved native constructor/member/accessor
identity; ordered parameter/result types; direction/transfer/nullability and count
relationships; error mapping; callback retirement; context; names/interface slots;
target/calling convention; and selected personalities. Member bindings refer to
checked identities, not delayed string lookup or integer roles such as GET/SCALE.

Carry typed copies with explicit origin/member maps through Checked, Core, CFG,
SSA and Native/CABI planning. Each detached verifier reconstructs the invariants
from that stage's actual type/member/call/cleanup graph. Digests identify artifacts
and compatibility; a matching digest alone is not a type, lifetime or layout proof.
Adapter plans validate their physical parameters against the native bridge and
the public declarations independently. Mutation tests alter each layer separately,
including binding, direction, ownership, count, slot, context and cleanup facts.

Keep three physical plans. Use installed C/Windows/GLib layout oracles, exact
target data layouts and actual calling conventions. Native Class/record layout
does not become a foreign layout. No application name, body pattern, numeric cap,
member count or recognized operation name admits a new API.

## Required channel mappings

| Native semantic channel | C declarations-v1 | Windows COM declarations-v1 | Linux GObject/GIR declarations-v1 |
| --- | --- | --- | --- |
| i32/u32, i64/u64 | Exact stdint types | Exact 32/64-bit SDK-compatible types | Exact GLib signed/unsigned widths |
| f32/f64 | float/double | float/double | gfloat/gdouble; matching GValue/GParamSpec |
| bool | Explicit C99 `_Bool`, correct ABI extensions | Explicit signed 32-bit BOOL; import nonzero becomes true, export 0/1 | gboolean with explicit normalization |
| Counted bytes | Pointer plus signed i32 length; output capacity/produced are explicit | Byte pointer plus LONG length/capacity/produced | guint8 array with exact GIR length, or explicitly selected GBytes owner |
| Text/view | Counted UTF-8 pointer/length; owned snapshot with exact matching free function | Counted UTF-8 byte pointer/length and explicit owned-result release | NUL UTF-8 gchar* with transfer, or counted UTF-8 via bytes/GBytes |
| Scalar POD | Target C layout and by-value ABI classification | Independently verified Windows POD input; result through typed out slot | Registered boxed copied record and usable GIR record fields/methods |
| Native Class | Nominal opaque unique/shared/borrowed handle | Shared native root through declared interface views | Shared native root through declared GObject wrapper |
| Foreign object/interface | Nominal handles with declared acquire/release/transfer | Typed interface pointer, IID and acquisition | Typed GObject/GType with exact transfer/nullability |
| Checked error | Signed 32-bit status, typed out plus error record | HRESULT and typed out; named error mapping | gboolean/typed result plus GError**, exact throws metadata |
| Synchronous callback | Typed C thunk, explicit userdata, call-only scope | Typed synchronous C-convention thunk in this explicit in-process ABI | Typed thunk plus closure/scope facts; retained signals use the protocol below |

POD storage includes mixed integer/FP scalar fields in declaration order, natural
target alignment and explicit padding. No native object header, references, bitfields
or inferred union active tags cross as POD. SysV aggregate classification and
Windows aggregate passing are separate verified lowering rules. Generated SDKs
include size/alignment/offset assertions; separately authored C/C++ definitions
and calls supply the independent oracle. Existing C union active-projection and
legacy C99 bool contracts remain unchanged (ADR 0141).

Counts are nonnegative, bounded by native representability and checked for
overflow before pointer arithmetic or allocation. Null plus zero is permitted
only for an explicitly nullable empty channel. Nonzero lengths require valid
foreign storage under the documented foreign obligation. Capacity/produced and
all mandatory out pointers validate before native invocation. Invalid bounds
publish no output. Mutable output uses staged storage when native failure or
conversion could otherwise publish partial output; commit initialized bytes and
produced count only after success. This has an explicit per-call allocation cost.

Owned text/bytes use a declared matching allocation/release domain. Counted UTF-8
preserves embedded NUL; NUL-terminated conversions reject it with a checked error.
Malformed UTF-8 rejects before typed exposure. Owned results are independent of
later native mutation. Ordinary GObject text property setters cannot return an
error: their native contract must be nonthrowing and accept every representable
GObject string value. Valid native text with embedded NUL uses a bytes/GBytes
property or an explicit checked conversion method; a text property export with
an unproved representability requirement rejects. Checked operations stay methods.

For imported text, an explicit UTF-8 result encoding on `owned u8[]` selects a
logical owned text channel. Validation and matching foreign retirement precede
exposure of the independent native byte owner, which can feed a native UTF-8
factory. A foreign allocation never acquires a static/receiver string lifetime.
The status/out result includes a payload count for both counted and NUL text;
the NUL form additionally promises a terminator beyond that payload.

## Owners, errors and lifetime

Unmarked native Classes remain unique. C creates/destroys their opaque owners;
there is no acquire/weak API and no automatic RC. Consuming parameters use owner
slots which are cleared once transfer begins. Prevalidation failure leaves input
owners with the caller; after transfer, native cleanup owns retirement even on a
checked failure. Borrowed owners are call-scoped and cannot escape.

Shared exports retain the existing intrusive native strong/weak authority and
explicit source clone/move rules. Each owned foreign reference contributes an
explicit native ownership duty. View pointers may differ; root identity does not.
Use personality-keyed weak wrapper caches without owning native-to-wrapper cycles.
An active invocation pins its shared root until conversion, callbacks and cleanup
finish. Native root retirement and wrapper retirement each occur exactly once.
Unique methods forbid consuming their active receiver via callback reentry.

Initialize out-owner slots to null and scalar/POD outputs to defined empty values
after pointer validation; stage acquisitions/conversions, publish only on success,
and release every provisional result on failure. Preserve meaningful nonfailure
statuses. C status uses 0 for ordinary success, positive explicitly declared
nonfailure values, and negative failures. HRESULT uses SUCCEEDED/FAILED, preserving
S_FALSE separately from out data. A declaration's named error/status mapping is
exhaustive and verified. Native exceptions never unwind across a foreign ABI;
allocation, conversion, context and declared native errors have distinct mappings.
The SDK specifies the bounded error record/domain/code and its release operation.

The C implementation spells the named mapping as
`[Foreign(error_domain="16", errors="BadInput=-1601,Fault=-1600")]` on a native
`throws Fault` member. The final case is its exact throws bound; more specific
cases precede it. `null_status="1"` selects a positive nonfailure outcome for an
explicitly nullable owned object result. These facts are common declarations;
target personalities retain separate physical error/status mappings. See the
[current C error protocol](../declaration-interop-16-c-errors.md) for qualified
implementation scope and outstanding work.

For C imports, `Foreign(error_factory="...")` explicitly binds a nonthrowing native
owned heap exception factory with i32 domain/status inputs and the exact declared
exception result bound. This supplies construction arguments without inferring an
application exception constructor. The native factory remains application code;
the import adapter only checks, transports and retires foreign results. See the
[C import notes](../declaration-interop-16-c-imports.md) for the qualified subset.

No promise validates forged/dangling foreign pointers or malicious NoEscape
implementations. Verify invalid ABI metadata before executable emission; safe
observer/fault hooks intercept duplicate/omitted retirement before any host free.

## COM slots, identity and context

Only QueryInterface/AddRef/Release have inherent slots 0/1/2. An interface's own
methods follow declaration order after its inherited prefix; read/write properties
expand to get then set unless separately specified member declarations select the
order. Foreign interface inheritance is single-base, acyclic and preserves exact
parent slots. Additional interfaces form separate views of the same native root.
Duplicate IIDs, conflicts with IUnknown, signature/slot collisions and incompatible
base mappings reject. Any published signature or ordering change requires a new
IID; SDK compatibility checking compares retained declarations, not just names.

QueryInterface has one canonical IUnknown identity, a stable supported interface
set and symmetric/transitive queries. Successful queries and owned out interfaces
acquire one reference; failure clears the out slot. AddRef/Release return values
are diagnostics, not client liveness oracles. Explicit in-process factories and
constructing-thread/apartment checks remain. Wrong-context operations fail before
touching native state. This follows the [QueryInterface rules](https://learn.microsoft.com/en-us/windows/win32/com/rules-for-implementing-queryinterface)
and [reference-count rules](https://learn.microsoft.com/en-us/windows/win32/com/rules-for-managing-reference-counts).

## GObject properties and bounded signals

Map scalar/text/object properties through their actual GParamSpec/GValue types,
access flags and nullable/owned result rules. Read-only properties have no setter;
get/set call resolved native accessors. Notify follows successful committed state,
not the unvalidated requested value. Export wrappers are nonfloating GObjects,
with stable live wrapper identity and one native root shared with active C views.

Add the bounded declaration `[Foreign(name="updated")] signal void updated(...);`
inside an exportable shared Class and the native statement `emit updated(args);`.
Only the defining Class emits; signatures are typed, synchronous, nonthrowing,
void-returning, with call-scoped arguments from the required channel domain.
There is no inferred property signal or general reactive dependency graph. The
native signal operation calls a typed attached bridge; it does not implement
application behavior in generated C. Independent source statements determine
which committed events occur. Native root and argument owners stay pinned through
delivery. No asynchronous scheduler or cross-thread event delivery is introduced.

The constructing thread performs connect/disconnect, emission and shutdown.
Connections carry exact closure/userdata/destroy authority. Disconnect marks the
connection inactive before observing completion; destroy waits for zero active
deliveries and foreign closure retirement. Self-disconnection defers environment
free until unwind. Reentrant object retention/release is supported with the active
call pin; recursive invocation of the same native retained registration keeps its
existing explicit reentry refusal. GIR records typed signal arguments, transfers,
counts, closure/destroy and scope facts. The generated GIR is scanned/compiled,
consumed by C/PyGObject and round-tripped through Astra's importer. Missing facts
reject. These mappings use [GI annotations](https://gi.readthedocs.io/en/latest/annotations/giannotations.html)
and [GObject signal lifecycle rules](https://docs.gtk.org/gobject/signals.html).

## Targets, personalities and opaque native units

One unchanged source may declare all three policies. New-profile invocations
explicitly select `--foreign-personalities=c,com` on Windows x64 or
`--foreign-personalities=c,gobject` on Linux x64. A native-only selection is
`--foreign-personalities=none`. Every invocation reports declared, active and
unselected personalities. An incompatible requested target rejects; unselected
ones are reported, not silently emitted. There is no all-three-active qualification
claim. Legacy invocations retain their current target/admission behavior.

Selecting no foreign facilities adds no COM/GLib runtime dependency or new native
ownership policy. Native layout remains compiler/target pinned. Extend the M15
native-unit schema with a new version for immutable foreign declarations, resolved
member origins and linkable bridge symbols. Continue reading valid /3 units;
never reinterpret a /3 unit as containing absent foreign facts. Validate transitive
closed types and contract identities; forbid executable imported bodies. Compile
adapters from declarative metadata and existing objects with producer source hidden.
Support at least one closed generic record/type crossing the native boundary.

## Implementation and qualification sequence

1. Implement the common descriptor, parser normalization and independent validators,
   then general C native bridges/imports and API A's unique processing session.
2. Extend the existing Windows target's actual channel/record/error/callback and
   opaque-unit prerequisites; derive COM imports/exports and execute native methods.
3. Add GObject mappings/signals, GIR and importer round-trip. Complete API A and
   freeze compiler/runtime/recipe identities before authoring API B.
4. Add the independent record-query/object-return API and transformations without
   emitter edits. A necessary general fix invalidates that freeze and requires a
   new unanticipated challenge. Retain each failed attempt and reason.
5. Execute independent providers/clients, O0/O1/O2, every O0/O2 leaf→component→adapter
   combination plus O1 smoke, symbol/open traces, safe source/stage mutations,
   rollback/lifetime/context/reentrancy and applicable memory/race diagnostics.
6. Build a fresh strict final compiler, freeze source/compiler/registry, run all
   applicable hosted registrations with original protocols/deadlines and every new
   SDK/native/foreign matrix. Exercise an installed SDK outside the checkout. Run
   current no-OS/async/M15 regression profiles under their effective permissions.
7. Reconcile live guides and capability/exclusion ledgers, commit only task paths
   with normal hooks, recheck preservation and publish through the installed tool.

Linux currently has GLib/GObject 2.88.4, GI 1.86.0 and PyGObject 3.56.3. LLVM/Clang
22.1.8, Vala 0.56.19, Meson 1.11.2 and Valgrind 3.27.1 are installed. The extracted
MinGW GCC 16.2.1 toolchain under the reusable build root is available without a
package installation. Exact source/tool/product identities accompany actual runs.

Read-only libvirt discovery found `win11` shut off with a managed save, 28 vCPUs
and 8 GiB RAM. **The user separately approved scoped Windows testing**: resume that saved
VM, use its existing console/serial devices, inventory the guest, temporarily
attach task-owned read-only test media, copy/run only task artifacts under a fresh
`%TEMP%\Astra16-*` directory, and capture hashes/results. Restore temporary live
media attachment after testing and leave the user's session running. Do not
discard the saved state, alter persistent VM/guest configuration, install software,
register COM, change snapshots/network/security/accounts or use unrelated guests.
If this route is unavailable, return its exact blocker and continue independent
Linux work. Native Windows G3/G8 cannot pass from cross-compilation alone.

Valgrind covers whole Linux executable paths in its actual scope; emitted-native
ASan and C/C++ ASan/UBSan/race tools receive separate instrumented-region labels.
Windows heap diagnostics and independent native destruction observers are separate
evidence. Thread-affine tests do not imply method-state race freedom. Final G0–G9
requires actual results, not adoption of this proposal or historical test totals.
