# Native borrowed slice channels v5

[buffer-v8](native-buffer-v8.md) separately defines owned runtime-array native
boundaries. Its ownership transfer metadata remains distinct even when PTR/I32
channels coincide. This borrowed profile is unchanged. BUFFER-1 permits implicit
`T[]` parameter borrowing and adds bool/mask/void* element views using the same
existing borrowed transport; elements do not add native channels.

Slices are intentionally ineligible as [GEN-1 generic arguments](../language/generic-functions.md).
A generic body may still use an ordinary concrete borrowed slice parameter or
local where baseline syntax permits it. Such concrete contracts survive Core
specialization and use this existing slice profile. No generic slice/ownership
contract or unresolved type parameter reaches NABI.

[Computed properties](../ir/properties.md) do not admit SliceType values because
ordinary plain native method results lack slice lifetime contracts. Accessor
bodies may use existing borrowed-slice callables normally. Property values use
existing channels and the existing effective-profile rules; no property profile
or borrowed property boundary is added.

F64-1 preserves this profile and admits borrowed f64[] through the same generic
SLICE(PTR,I32) channels. A by-value f64 elsewhere selects [fp64-v6](native-fp64-v6.md);
the slice itself has no F64 channel. Old slice-v5 signatures and dumps stay stable.

OBJ-BOUND-1 borrowed ClassType parameters coexist with slice-v5 without changing
the profile: `process(borrowed C c, borrowed int[] values)` retains two logical
parameters and maps to PTR plus SLICE(PTR,I32), three physical inputs. A method's
implicit receiver is still a separate first PTR. Vector and owned Resource
channels use the same existing grouping/order; ClassType and its noescape contract
remain exact upstream. No object group/type/profile or LLVM `nonnull`, `noalias`,
`readonly` or `byval` promise is introduced. See
[borrowed object parameters](../language/borrowed-object-parameters.md).

OBJ-LIFE-1 constructors reuse the slice-v5 parameter group without changing its
contract. `init(borrowed f32<4>[] blocks)` physically receives receiver PTR,
blocks.base PTR and blocks.length I32, then returns void. Vector parameters and
owned/borrowed Resource PTR parameters coexist under the same profile. Argument
capture and owned transfer commit precede constructor invocation; storage reservation
has no argument effect. The reference is published only after normal return.
No lifecycle-v6 profile is introduced; borrowed ClassType uses existing PTR. See
[lifecycle IR](../ir/object-lifecycle.md).

METHOD-1 adds an independent implicit receiver PTR before ordinary parameter
groups. A method `int sum(borrowed int[] values)` has one explicit semantic
parameter, one SLICE(PTR,I32) NABI group and three physical inputs in this order:
receiver PTR, values.base PTR, values.length I32. NativeSignature.receiver holds
the first channel separately; physical_parameter_count includes all three.
SliceValue remains whole through SSA; expansion occurs in LLVM after ordinary
receiver/argument evaluation and owned transfer commit. Existing slice-v5 also
admits method vector and owned Resource channels. There is no method-v6 or
NativeReceiverType, and no new ownership, noalias, readonly or nonnull attribute.
See [method IR](../ir/methods.md).

`borrowed T[] s` is one exact SliceType parameter with a BORROWED_NOESCAPE
contract through checked code, Core, CFG and SSA. NativeTypeMapper.map_parameter
requires that contract before mapping it to one NativeSliceType group:

```text
(native-abi slice-v5
	(function #0 "sum"
		(linkage native-internal)
		(signature
			(parameters
				(parameter #0 SLICE(PTR,I32)))
			(result I32))))
```

| Semantic parameter | Group | Ordered physical arguments |
| --- | --- | --- |
| `u8 mode` | U8 | i8 |
| `borrowed f32<4>[] blocks` | SLICE(PTR,I32) | ptr, i32 |
| `f32<4> gain` | VECTOR(F32,4) | `<4 x float>` |
| `borrowed int[] counts` | SLICE(PTR,I32) | ptr, i32 |
| `owned Resource r` | PTR | ptr |

These are five semantic parameters, five NABI groups and seven physical LLVM
arguments. All slice element types share the same physical group. Exact
semantic call checks still reject signedness, element or vector-shape mismatch.
NativeSignature.physical_parameter_count describes expansion without changing
its semantic-parameter ordinals. NativeSliceType is a distinct parameter group,
not a NativeScalarType or native result channel.

One slice parameter selects program-wide `SLICE_V5` / `slice-v5` unless a
by-value f64 native channel requires the later fp64-v6 profile.
It permits prior direct scalar and vector channels, while preceding profiles
reject slice groups. Local slices alone do not affect profile selection.
Both old scalar and vector signature dumps remain byte-for-byte stable when
the program has no slice parameter.

The callee receives runtime length as semantic int/I32. Nonempty slices require
valid suitably aligned live storage of the exact element type. An empty slice
may carry null. Native callers are trusted to supply a well-formed value;
there is no boundary descriptor or dynamic revalidation. Callee indexing still
checks `0 <= index < length` before calculating an address or accessing memory.
That proof makes a separate null check unnecessary. Parameters carry no noalias,
readonly or nonnull attributes.

Argument evaluation and OWNBOUND capture/commit occur before physical expansion.
LLVM extracts the adjacent components from one bound view and reconstructs one
`{ ptr, i32 }` value at entry. Copies, forwarding, recursion, aggregate phis and
scalar/vector memory retain their existing semantics. There is no runtime borrow
token, descriptor, ownership transition or new storage convention.

NABI model/verifier/dumper remain independent of semantic and LLVM objects.
Compiler versions do not promise binary compatibility for this internal ABI.
C/VAPI slices, exports, unqualified or owned parameters, and all slice results
remain unsupported. See [ADR 0047](../decisions/0047-native-borrowed-slices.md).
