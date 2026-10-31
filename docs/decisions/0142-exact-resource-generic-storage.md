# Exact Resource generic storage

Surge 10's general checked-body template now admits exact Resource arguments as
well as the existing exact heap Classes. The same
`lib/astra/collections/vector.astra` declaration grows, appends, inspects, takes,
replaces and destroys both domains. The legacy ExactHeapClass constraint keeps
its Class-only argument rules and existing source refusals.

The generic key and slot type carry a semantic element identity. A Resource
slot retains its original nominal handle and declared foreign destructor; a
Class slot retains exact heap provenance, Class destructor and allocation free.
Core and CFG check those distinct authorities. SSA uses the existing persistent
scalar responsibility events for every participating named Resource, including
immediate append/replace disarms and fresh take acquisition. Ordinary Resource
cleanup outside these compositions retains its previous contract.

Native metadata copies exact Resource parameter, result and storage ownership
roles. `NativeScalarOwner`, shared with owning enum fields, carries the nominal
name and original cleanup symbol. Resource slots freeze that declaration in the
independent native Class plan. A forged field and forged matching generic key
cannot replace the original declaration. Signature validation independently
checks pointer channels and ownership roles without retaining semantic or SSA
objects. This is private native metadata, not a new external C/GObject ABI.

The hosted backing descriptor remains base/count/capacity. Live count, rather
than pointer nullness, determines Resource occupancy. Null owned Resource values
may be inserted, moved, replaced, taken and destroyed; cleanup skips null. Class
elements retain their existing nonnull occupied-slot checks. Resource teardown
calls its declared C destructor, which owns its allocation policy. It never
also applies Class deallocation. Reserve moves carriers and clears old slots;
take preserves remaining order, replacement admits the incoming owner before
retiring the previous one, and teardown runs in reverse current element order.

The three-specialization witness checks exact independent allocation/destruction
traces, growth, inspection, replacement, removal, failed negative reserve and
null Resource take at O0/O1/O2 and under unsuppressed Valgrind. Independent proofs
release upstream graphs, reject wrong cleanup contracts in Core/CFG/SSA, omit
both SSA disarms, forge native keys/destructors/parameter roles, and substitute
an LLVM-valid foreign destructor call before restoring each artifact.

Seven selected suites pass (`surge-10-generic-resource-first`), including the
67-command generic public harness, three generic TAP proofs, historical Bag
controls, builder-free native controls and the 206-command G1 public aggregate
regression. Earlier syntax/schema probe failures remain in the task runtime.
This closes the Resource storage component, not G2: copyable and owning record
elements, broader generic methods and the remaining G3–G9/applications continue.
