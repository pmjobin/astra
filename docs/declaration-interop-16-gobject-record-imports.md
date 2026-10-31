# M16 boxed GObject record imports

A declaration-driven GObject import can specify
`records="Sample=SdkSample:sdk_sample|Pair<f64>=SdkPair:sdk_pair"`.
Each binding names the exact native scalar record, SDK C boxed type and SDK symbol
prefix (`_get_type` and `_free`). Empty, duplicate and malformed bindings reject;
every imported record channel requires a binding. Bindings are immutable import
metadata and participate in exact origin identity/equality at every stage.

The SDK record uses declarations-v1 ordinal/member field names, GLib scalar
storage and natural LP64 alignment. Generated static assertions independently
check C field types, offsets, size and alignment. Runtime admission checks that
the supplied GType is boxed. Input fields are copied into a scoped SDK record;
a full output stays under the SDK's matching free operation until checked status
and all result validations pass. Native storage is never reinterpreted as GLib
storage. Mechanical C POD forwarding is emitted once for import-only and combined
import/export products.

The independent provider exercises a mixed scalar record (including gboolean32,
u32/u64 and floating point), a closed generic record, null success refusal and
provisional checked failure. Native clients observe values and exact boxed free
counts. Detached Core/CFG/SSA/NABI/CABI mutations replace the boxed SDK binding
behind unchanged logical signatures; each validator independently refuses it.

This is intermediate qualification. GIR round-trip, retained signals, native
composition, target personalities, frozen-compiler SDK work and final M16 gates
remain open.
