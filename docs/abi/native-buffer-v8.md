# Native owned-buffer ABI: buffer-v8

Record-element owner boundaries use [struct-elements-v11](native-struct-elements-v11.md), with the same outer PTR/I32 transport and independently owned recursive element shape. This document retains the accepted numeric/primitive buffer-v8 contract.

`buffer-v8` is the monotonic native profile for owned runtime-array parameters
and results. Native v0–v7 remain frozen. Borrowed `slice-v5` is unchanged.

An owned buffer and a borrowed slice can both physically use PTR plus I32, but
their contracts are distinct: only the owner boundary transfers unique cleanup
responsibility. Type identity alone cannot select the boundary contract.

| Source contract | Native plan | LLVM boundary |
| --- | --- | --- |
| `T[] values` / `borrowed T[] values` | Existing borrowed NativeSliceType, no cleanup | PTR base, I32 length under existing slice-v5 rules |
| `owned T[] values` parameter | Complete ordered NativeBufferParameterPlan; exact element layout and static deallocation transfer | Two ordinary `ptr, i32` parameters |
| `owned T[]` result | NativeBufferValuePlan result, unique owner responsibility | Backend-only `{ ptr, i32 }` return carrier |
| Class containing owned buffers | Existing object parameter/result contract | Existing object PTR and OBJ-RET storage protocol; no field channel expansion |

No capacity, allocator pointer, destructor function, header address, active flag
or refcount travels in a buffer signature. The native program contract supplies
the static allocator realization. Future static strategies need compatible
boundary qualification; BUFFER-1 introduces no per-value strategy dispatch.

```astra
owned f64[] relay(owned f64[] values) { return move values; }
```

```llvm
define internal fastcc { ptr, i32 } @astra.fn.0(ptr %p0, i32 %p1)
```

Names/ordinals are illustrative. The real dump includes explicit ownership
parameter/result plans even though borrowed channels have the same leaf kinds.
SSA has no aggregate buffer Value: the carrier is created/extracted only by
LLVM lowering. Moves, arguments and results never copy element storage.

Mixed scalar, borrowed slice, owned buffer, Resource, Class and supported struct
channels preserve source ordering and exact group boundaries. Existing OWNBOUND
left-to-right semantic move capture remains separate from the physical transfer
commit immediately before invocation. A buffer disarm is one null/zero group
action; the callee receives the captured complete pair.

The verifier rejects buffer metadata under old profiles, missing PTR/I32 leaves,
wrong order or offsets, incomplete result plans, unrelated result carriers,
invalid element transport and inconsistent ownership group associations.
SSA-to-NABI validation proves exact correspondence before LLVM lowering.

Local allocation does not by itself select a new *boundary* profile. A function
or module without owned buffer parameters/results can keep its prior native
profile while using explicit local buffer instructions.

CABI, C exports and VAPI do not acquire owned-array mappings. An owned `f64[]`
is not a C `double*`; C floating pointers and C aggregates remain excluded.
See [the language contract](../language/owned-runtime-arrays.md) and
[host allocation](../backend/host-buffer-allocation-v0.md).

Generic array owners materialize to these existing concrete plans before CFG. Record owners use struct-elements-v11. Equal PTR/I32 carriers do not equate owner and borrowed-view roles. No additional ABI profile is introduced; see [generic array IR](../ir/generic-owned-arrays.md).
