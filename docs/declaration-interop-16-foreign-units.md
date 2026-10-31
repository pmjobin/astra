# M16 opaque unique C units

Declaration-driven foreign Classes can be published in the new
`gnu-x86_64-lp64-foreign-units/4` interface schema. Historical plain native units
continue using `/3`; the reader accepts both and refuses a `/3` artifact carrying
foreign metadata. The compiler, target, layout, declarations, transitive objects
and native symbol identities remain pinned by the existing native-unit protocol.

The `/4` schema records each exported foreign root's complete immutable contract,
including explicit personality selection, and the exact public bridge symbol
inventory. Import reconstructs checked declarations and compares their resolved
contract with that metadata. Member order is preserved even when a storage field
follows a constructor. Foreign/channel attributes survive declaration serialization;
executable method/property bodies remain forbidden. Imported roots use their
existing compiled bridge implementations, avoiding duplicate adapters in the
consumer. Generated C POD forwarders contain mechanical layout conversion only.

The qualified channel slice includes a unique native owner, an owning component
field, properties, mixed bool/integer/FP POD, a closed `Pair<f64>`, a synchronous
callback, borrowed bytes, independent owned byte results and checked native
errors. Owned byte pairs carry their full native physical result contract.
Namespaced error cases use exact qualified native identities; their C error macro
suffix is `qualified_` followed by the SHA-256 of that identity. Existing simple
error names retain their previous macro spelling.

The portable recipe removes task-owned producer source copies before compiling
the component or adapters. An `openat` trace confirms that adapter generation
reads the transitive interfaces/objects and no producer source. Independent C and
Astra consumers execute eight O0/O2 leaf/component/adapter combinations and one
O1 combination. A separate native-only composition
checks absent Class bridge symbols and absent GLib dependencies. Three executed
clients receive unsuppressed memory checks. Re-sealed declaration mutations test
prefix, member name/selection, error code, bool ABI, callback ownership and body
authority; explicit selection drift and schema downgrade also reject.

The companion JSON records exact source/receipt identities and integration checks.
This is an intermediate Linux unique-C prerequisite. Shared COM/GObject opaque
SDKs, retained native signals, the frozen second-API challenge and the final
complete G0–G9 qualification remain unfinished.
