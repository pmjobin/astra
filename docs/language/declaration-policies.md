# Built-in declaration policy registry

`astrac --policy-registry` lists the compiler's versioned policy vocabulary,
numeric IDs, availability, selected placement and current argument forms.
The canonical spelling lookup is `Source.DeclarationPolicyRegistry`; native
parser dispatch and concurrency spelling resolution use that lookup.

Registration is separate from implementation. `AVAILABLE_SELECTED_PROFILE`
means the compiler implements the documented bounded declaration contract.
`RESERVED_UNIMPLEMENTED` means the attribute cannot grant a source guarantee.
The selected function forms of `[CImport]` and `[CExport]` are implemented;
see [the C policy guide](c-policies.md). `[CExport]` also admits selected
[opaque Shared Class wrappers](c-class-exports.md). `[COMExport]` composes with
that bridge under the [Windows x64 COM contract](com-exports.md). `[COMImport]`
admits selected [nominal Windows interface owners](com-imports.md).
`[GObjectExport]` adds selected [native GType/property/signal exports](gobject-exports.md)
with real GIR/typelib consumption. `[GObjectImport]` identifies selected
[typed Source/VAPI bridges](gobject-imports.md) and canonical GIR products.
Existing `extern(C)`/`export(C)`, GObject imports
and GIR tools retain their accepted meanings. Candidate `[Reflect]`, `[Pure]` or `[Lazy]`
attribute spellings do not replace existing descriptor commands, effect proofs
or native lazy-property syntax.

Policy-specific checked values retain their existing independent authorities:
`ConcurrencyPolicy` for admitted sharing/monitor/instance/thread/actor flags,
`AllocationPolicy` for allocator domain/capacity/alignment/hooks,
`PodRepresentation` for exact scalar C layout, and `ForeignClassPolicy` for
opaque C/COM identities, lifetime and context roles. Their snapshots, mutation
guards and downstream verifiers remain authoritative. Registry IDs do not replace the
existing concurrency bit mask or any native ABI field. Native objects acquire
no new metadata or services merely because the compiler has a registry.

Current string-valued annotation arguments still resolve through those typed
validators; the registry does not introduce a generalized macro system. Existing
placement, duplicate/conflict, inheritance and specialization restrictions remain
in force. Mixed new foreign policies, broader attribute composition and new
foreign object adapters are continuing Surge 14 work, not accepted by this
registry foundation alone.

The focused recipe `tests/interop-tooling-14/policy-registry.py ASTRAC
EXTERNAL_OUTPUT` compares commuting Shared/Monitor forms through checked
semantics, Core, CFG, SSA, native ABI and LLVM; executes real C calls at O0/O2;
and checks duplicate, placement, argument, incompatible and unavailable-policy
refusals. The preexisting concurrency policy mutation proof and shared/singleton/
actor execution registrations also run against the rebuilt compiler. These
checks preserve the earlier diagnostic text, including the existing generic
Actor/Monitor identity refusal.
