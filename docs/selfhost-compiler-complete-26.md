# Compiler-complete 26: current qualification

Milestone26 is **PARTIAL**. Whole original compiler admission, native object
generation, integrated linkage and full compiler performance qualification
have not been established. Bounded current regressions remain separately
attributed below. No Stage1 or self-host claim is made.

## Post-restart O0 results

The fresh build at `7830a0d` took 47:25.62 with 2,215,952 KiB peak RSS. Its
compiler SHA-256 is
`9ae694a5aed6faba8f633314c4712334e4067f2596aafbbfa1d3155559664fdc`.
`native-gen6-independent-audit.json` binds all 180 production modules, 195
consumed archived Git inputs, the exact LLVM 23.1.4 tool identities, and 115 raw
command stream pairs. The earlier user-terminated attempt remains preserved.

Two nested record value programs, two flat record programs, and three slot
programs generate native objects, link, and execute to 42 under Astra O0. The
seven Astra and nine C0 executables have clean unsuppressed Valgrind receipts.
The record controls refuse 48 source model and 36 LLVM-valid perturbations.
Five slot negatives and two C0-valid nested Class/Error memory cases refuse with
their destination sentinels intact. All three slot LLVM and ELF pairs match the
prior artifacts. The flat record comparisons across different input paths retain
their CallerInfo byte drift. `record-values-gen6-same-path-O0` replays the exact
prior input paths and obtains byte-identical raw LLVM and ELF for both programs.

`original-gen6-frontier-O0` reauthenticates all 180 original compiler files and
ten dependencies against the initial Git base. The complete native attempt
takes 126.12 seconds, exits 3 with `RECOVER_FLOW 3 307096 0`, and preserves its
output sentinel. The first refusal is the original `bag.astra` declaration at
bytes 133–649. Complete compiler native generation remains at zero of two
profiles. The concrete collection payload, independent graph55 owner proof,
and compiler scale qualification remain open.

## Ordinary Class record memory

The candidate admits copyable record fields in ordinary Classes. It uses the
nested source layout for memory and the established flat carrier for native
values. The load and store helpers belong to the LLVM module. The consumer checks
record sizes, alignments, offsets, helper bodies, and access addresses against
the source layout and actual receiver. The new control substitutes a null
address in each reachable record field call, checks LLVM validity and verifier
refusal, and restores the valid call before emission.

`native-classrecordcheck2-O0` passes original C0 semantics for all 180
production modules and the test host in 52.08 seconds. The initial wrong
verifier argument remains recorded as a failure. The pinned Astra formatting
check passes on all five changed sources. The Python formatter refused the host
3.15.2 executable against its 3.15.0 pin, so the existing Python recipe was
restored. Both original C0 record field oracles execute to 42 with clean memory.
The second oracle replaces the field and verifies the earlier record copy.
The frozen `119829c` O0 host built in 48:47.14 at 2,285,868 KiB peak RSS. Its
SHA-256 is `8de498cbee8cabeb7e5e0382849fb67211c5a8ee49329c2baa9ade8bd738192d`.
Both Class record programs passed independent LLVM verification, native
linkage, exit 42, and unsuppressed Valgrind. The nested Error memory refusal
preserved its output sentinel. Two flat record and three owner slot programs
also passed native execution and memory checks. Five slot refusals preserved
their output sentinels. `native-gen7-independent-audit.json` rechecks 195
Git-authenticated inputs, 46 tool identities, source and native artifact hashes,
and command streams. Its SHA-256 is
`ed5e67cdd7a7e0b925c9cd530ca532603908378e2a1c77d993faf5338bea1243`.

## Dynamic arrays of copyable records candidate

Dynamic record arrays use the existing owned buffer descriptor and owner checks.
Allocation uses the nested element size. Indexing uses a type-specific bounds
helper and the record memory load or store at its checked address. The independent
consumer checks the element layout, allocation stride, bounds helper, and exact
use of the returned address. The scalar array helpers retain their existing
inventory. New controls substitute the allocation size or access address and
restore the valid instruction after checking the verifier refusal.

The original C0 fixture grows an owned Class field by swap, checks adjacent and
zero-initialized records, reads through a borrowed parameter, and exercises normal
and error cleanup after transferring an array. `record-arrays-oracles1` verifies
its raw C0 LLVM and records exit42 and clean unsuppressed memory at O0 and O2.
The C0 semantic check of all 180 production modules passes in 50.98 seconds in
`native-recordarraycheck2-O0`. The first check retains its owned-field alias
diagnostic. The corrected code uses temporary borrows. The frozen `64ca46e`
O0 host admits the 240-node array program through SSA, then refuses its LLVM
physical contract with exit 5 and an intact sentinel. The hardware-breakpoint
trace reaches the bounds helper signature after checking the nested layout
and load/store helpers. The signature previously accepted only scalar
elements. The candidate distinguishes scalar and independently verified record
element types and retains the same exact GEP and bounds checks. Record element
layouts are also available for arrays that occur only in local storage.

`record-index-kernel2` binds 17 production declarations and checks actual LLVM
graphs at O0 and O2. Both profiles accept the scalar and nested record helper
and refuse six LLVM-valid controls, including wrong element identity, a packed
layout, and modified bounds and GEP operands. The initial build retains its
missing LLVM declaration diagnostic. The corrected full Astra native replay
is pending.

The frozen `2d63b55` observer accepted both original `Bag` payloads on all 190
unchanged original inputs, including `Bag<FlowGraph>`. RecoverFlow advanced to
the original `Vector` declaration at bytes 140–1018 and exited 2. The four closed
`Vector` payload layouts passed storage checks. The declaration and executable
methods still require Flow validation. `record-array-flow-original` retains
the input ledger and raw result. Complete original native generation remains
at zero of two profiles.

## Original Vector specialization coverage

The frozen `85cd40c` observer admits the original `Vector` and its focused
`SlotValue` client through Typecore and Flow with 185 Flow nodes. Removing a
concrete member and duplicating another both cause refusal. Restoring the
original plans passes the complete generic verifier. On the 190 unchanged
compiler inputs, the same observer still refuses the original `Vector`.

The hardware-breakpoint inspection reads the frozen observer's 223 actual
specialization rows. `Vector<Utf8Message>`, `Vector<SourceEntry>`, and
`Vector<Token>` each lack `init` and `replace` plans. `Vector<SyntaxList>` has
all eight member plans. The original refusal reproduces after the inspection.
The setup attempt before the inferior was running retains its debugger failure.
The successful inspection receipt SHA-256 is
`5e1bab250ab6858dd33f9e149626c55541bfeef15acf0237c5c552eff81eea5c`.

The forward-field fixture reproduces the omission when an earlier field needs
`Vector<LateValue>` before `LateValue`'s fields have types. Its original C0
oracles execute to 42 with clean Valgrind at O0 and O2. The candidate revisits
closed Class specializations after checking declaration heads. Their missing
member signatures are established before concrete body checking. All ordinary
generic verification and the 256-instance ceiling still apply. The frozen
`cf2a4c2` observer passes the forward fixture with 103 Flow nodes and the
missing and duplicate member controls. All four original `Vector` declarations
pass on the 190 unchanged inputs. The next refusal is `LlvmStorageCursor` in
`compiler/backend/llvm/class-storage-slots-check.astra`, bytes 211–6700.

## Opaque handle and counted C import candidate

`LlvmStorageCursor` stores non-owning `void*` values and owned arrays of those
values. Its constructor counts the incoming blocks before allocating the arrays
and writes through initialized fields. The candidate uses the canonical opaque
pointer type, preserves array owners and bounds, and verifies the initialization
of constructor fields and scalar locals against the original binder. It checks
every pointer load/store address and the unqualified C import conventions.

`raw-pointer-c-oracles2` and `raw-pointer-constructor-oracles1` execute to 42 at
O0 and O2 under original C0 with clean unsuppressed Valgrind. The raw C0 LLVM
uses `ptr` and a full-width `i64` result for the actual C provider. The first
oracle attempt retains the refusal of a link option on the LLVM dump command.
`opaque-index-kernel1` matches the actual array helper declarations. Both
profiles accept the opaque pointer GEP and refuse the LLVM-valid address-space
and pointer-slice controls, alongside the existing scalar and record controls.

The exact original hosted-files C0 dump separately verifies both byte-buffer
imports with `(i32, ptr, i32, i32, i32)` channels. The candidate binds that
transport only to the explicit `buffer_abi = "u8-i32"` declaration and its
borrowed byte descriptor, with the actual data pointer and extent operands.
Fresh integrated Flow and native qualification are pending.

The frozen `572a933` native O0 host now passes the record-array fixture through
all stages and real native execution, with 324 LLVM blocks, twelve memory-layout
controls and clean unsuppressed Valgrind. The local-only record array and
forward-Vector fixtures also pass. Long assignment/call, Class record memory,
flat record and owner-slot checks pass. Its hosted-files refusal precedes the
later opaque/counting C changes. Its full-original attempt retains the actual
`LlvmStorageCursor` refusal. Both failed raw sequence steps remain failed.

The frozen `2a14329` observer builds in 23 minutes 47.46 seconds with
1,660,140 KiB peak RSS. Its pointer-array fixture reaches 31 Flow nodes and
fails the independent Flow check. The pointer constructor refuses its Class
declaration, and hosted-files refuses the original `this.descriptor` expression
at bytes 1974–1989. The forward-Vector fixture passes. The full 190 original
inputs fail Typecore with the exact `generic instance resource limit`
diagnostic in `SourceSet`, bytes 5114–5385. These failed raw receipts remain
unchanged. The 256-instance ceiling still applies. Source review also found
that both conditional-type equality queries lacked the canonical opaque-pointer
case. Both queries now include that case. Its integrated proof is pending.

Hardware-only observation of the frozen hosted-files failure finds the real
`this.descriptor` receiver at symbol 155 in concrete function 150. Storage
construction succeeds with 70 slots and no boundary. The field token itself
has no completed Binder target. Normal Typecore call checking still sends the
new counted-buffer and full-width scalar C signatures down its deferred-call
path. That route skips ordinary field-argument completion. The candidate now
runs the existing authoritative argument checking for those exact admitted
signatures, using ordinary Binder-reference completion before Flow. The all-module
C0 frontend check passes. Native integration remains pending. The first
hardware observer retains GDB's own callback-deletion crash. Its corrected
stable-breakpoint replay preserves the original target refusal.

## Indexed mutation queries candidate

LLVM emission and its independent consumer previously scanned all Flow nodes
for each scalar mutation query. The producer now indexes mutated symbols after
building Flow. The Flow consumer reconstructs the index from retained nodes and
compares every symbol. A consumer cannot treat an unchecked cached flag as a
source fact. The six existing LLVM call sites use the checked index.

`mutation-index-kernel3` matches nine actual source AST declarations. Across
16,384 retained rows and 4,096 symbols, the indexed query agrees with the exact
previous scan at O0 and O2. Six controls reject missing, extra, zero-symbol,
wrong-length and invalid-source entries. Removing mutations and rebuilding the
index clears their old flags. Both profiles return 42 with clean unsuppressed
Valgrind. The first two attempts retain their missing capsule fixture and
recipe-precedence setup failures. The all-module C0 semantic check passes in
55.00 seconds. The real Flow entry also has missing/extra-index corruption and
restoration controls for the next native candidate.

`mutation-index-cost2` separately compares matching 16,384-row populations and
262,144 queries using original C0, three timed executions per variant/profile,
and the actual prior source from `c4884a8`. The candidate includes index
construction. Minimum elapsed samples are 15.5142 versus 0.00421 seconds at
O0 and 2.98505 versus 0.00254 seconds at O2. GNU time CPU/RSS receipts and all
three samples are retained. These are query-kernel measurements. Matched
whole-compiler execution and cold-build costs remain pending. The first cost
recipe retains its missing diagnostics-provider failure.

## Source-bound ordinary method lowering candidate

The original source limit arises while the previous semantic route normalizes
ordinary Class members through the generic instance table. The candidate has
a separate table indexed by each original method's Binder symbol. A direct
method has a fixed nongeneric declaring Class, no type parameters and no type
arguments. Its body is copied from that exact declaration, receives the actual
borrowed receiver parameter, and obtains its ordinary checked signature.
The existing bounded source maps and callable-key bytes are reused.

The independent consumer verifies each direct source's original Class, copied
AST, bindings, references, signature and hidden receiver. It checks every map
slot across both tables, their nonoverlap and the direct table's inverse symbol
mapping. The generic instance limit remains 256. The syntax, map and SSA limits
also apply. Native ABI planning, field/constructor proofs and both backends read
the actual source plan for either kind of callable. Independent owner and field
authority still passes through the existing consumers.

`direct-method-oracles1` independently executes the focused 262-member source
and the genuine 256- and 257-specialization sources with original C0 at O0/O2.
All six ELFs return 42 with clean unsuppressed Valgrind. The previous
`572a933` host refuses 262 ordinary members, accepts exactly 256 real generic
instances through native LLVM generation, and refuses 257 real instances.
Both refusals preserve their output sentinels. The focused ordinary fixture
has two Classes, 130 methods per Class, two constructors and linked member calls.
It supplies boundary evidence for this feature.

The candidate passes the all-production C0 frontend check. The first check
retains its stale receiver-lookup variable diagnostic. The observer has five
restored controls for source origin, enclosing Class, type-argument count,
inverse mapping and receiver ownership. Actual candidate execution, native
integration and complete-original qualification are pending.

## Constructor-owned locals candidate

The original `SyntaxArena` initializer creates local `Vector` objects and moves
them into owned fields. `nested-class-field-oracles1` independently reproduces
that allocation-and-move shape, plus a call through the owned child field.
Original C0 returns 42 with clean unsuppressed Valgrind at O0 and O2. The
previous `572a933` native host refuses the parent constructor, bytes 186–302,
with its output sentinel preserved. The tracked fixture has the same C0 AST
as the vetted source.

The source walk now checks an actual Class allocation's constructor, signature,
receiver and argument channels against the current initialization state. A
fresh owned Class local becomes usable after its initializer passes that walk.
Moving it into a field retains its lexical Binder slot. The enclosing Flow
pass checks every constructor body, while Core, SSA and LLVM retain their
ownership and retirement checks. The ordinary initialization walk still
establishes each field once. Its actual native qualification is pending.

The all-production C0 frontend check passes in 54.58 seconds. The updated
semantic observer check passes in 32.09 seconds. Its constructor controls check
before/after/cleared local state, the owned local flag and the actual callee
signature. The direct-method control successor adds disabled-native-profile
and empty-table cases. Missing source-plan queries return an explicit empty
value. The frozen `2569232` observer retains its earlier five-control source.
Both new control groups await execution by their matching product.

## Direct-method and native dispatch observations

The frozen `2569232` observer executes all 262 ordinary members through checked
Typecore and Flow, with zero generic instances. Five restored source/receiver
controls pass. The genuine 256-specialization source passes Flow with 2,057
nodes, and 257 specializations retain the exact resource refusal. The pointer
array, original hosted-files and forward-Vector sources also pass Flow.
The pointer constructor retains a real SIGILL assertion, so the initial
focused worker defers its full-original Flow run.

`direct-original-typecore1` separately executes all 190 unchanged read-only
original inputs through the checked Typecore and independent source-plan
verification. It completes in 195.60 seconds, with both original generic Class
declaration contracts passing. The separately printed restricted member-body
predicates remain literal diagnostics. This supplies Typecore evidence only.
Original whole-compiler Flow, Core, CFG, SSA and native products remain unproved.

The frozen `4afb133` native O0 host executes the opaque pointer-array program
to 42 with clean unsuppressed Valgrind. Its function-only module source generates
real retained-function objects at O0 and O2. Both objects preserve the actual
private source function. The native mutation-index entry passes its missing,
extra and restoration controls on 11,712 Flow nodes. Its raw sequence also
retains post-SSA assertions across the earlier array, Class, flat and slot
programs. Several scripts stop before writing their final result. The separate
independent audit rechecks all 195 consumed archived Git inputs, all 46 tool
identities, raw command streams, the pointer ELF and both module objects.
Every failed and incomplete receipt remains explicit.

The natural pointer-constructor backtrace reaches
`SyntaxArena.get_node_initializer` from `recover_constructor_statement`.
An assignment was sent to a declaration-only accessor before its expression
branch ran. The source walk now selects the accessor for the actual AST kind.
The native post-SSA backtrace reaches `get_token_extern_keyword` while scanning
foreign declarations. The extended foreign predicate lacked its function-kind
guard before that accessor. The predicate now checks the symbol kind, owner
and AST kind first. The protected arena assertions stay active. The source
observer successor scans every real Binder symbol through the foreign query
before native emission. The matching production and observer C0 checks pass.
Actual rerun qualification for these corrections is pending.

## Heap-Class field population candidate

The unchanged original `SyntaxArena` has 186 private fields. The focused
`wide-class-oracles1` sources independently exercise 128, 129 and 186 scalar
fields with original C0. All six O0/O2 ELFs return 42 with clean unsuppressed
Valgrind. The frozen `572a933` Astra host emits verified LLVM for 128 fields
and refuses 129 and 186 in Flow, preserving both output sentinels.

The candidate extends heap-Class field admission to its actual Binder-indexed
population. Each field still requires its source node, owner, type and flags.
The layout's 16 MiB payload bound remains, and the independent consumer now
checks the aggregate extent before adding each child. By-value records retain
their 128-field domain. This is a heap-Class source-capacity change required
by the original source. The generic 256 and SSA 8,000,000 ceilings remain.

The tracked 186-field fixture passes the guarded formatter's AST preservation
checks. The all-production and observer C0 frontend checks pass. New observer
controls perturb the actual field binding, qualifier, field population,
payload extent, ordinal and offset, restoring each before continuing.
Their execution and native integration remain pending.

The frozen `29d9ea4` observer subsequently passes all three 128/129/186-field
sources through Flow. Each passes two restored source controls and four
restored layout-table controls. The constructor-local controls also pass.
These are actual semantic/Flow results, with native integration still pending.

`direct-source-independent-audit1` reauthenticates the frozen `2569232`
observer's 107 consumed archived Git inputs and its tool identities, all 190
unchanged original target inputs, eight original-C0 oracle ELFs and their
memory receipts. It preserves the raw pointer-constructor assertion and
attributes the 195.60-second original Typecore result to that exact observer.

The separate `computed-property-oracles2` sources exercise the arithmetic,
nested-field and method-call getter shapes used by original `SyntaxArena`.
Original C0 executes all six O0/O2 ELFs to 42 with clean memory. The previous
Astra host refuses each. The first oracle attempt retains its C0 rejection
of a direct field allocation. The successor uses the required owned local
and explicit move. Computed getters remain a source-admission obligation.

## Computed getter body candidate

The frozen `bd06bf8` observer passes all eleven focused source/Flow checks,
including the seven ordinary-method controls, the real 256/257 generic
boundary, the corrected pointer constructor, five constructor-local controls
and the foreign-declaration scan. A separate all-190-original-input module
Flow attempt takes 230.04 seconds and refuses `CfgProgram`, bytes 2815–3211.
Its owned dependency chain reaches the still-unadmitted original `SyntaxArena`.
The detailed declaration survey remains a separate in-flight observation.

The getter candidate copies the actual accessor body and declared result into
an ordinary private function with one real borrowed Class receiver. The source
accessor's Binder symbol keys the direct-method table. The property window
retains the exact result-type node and body edges. The independent consumer
checks their correspondence, normalized function scope, signature, receiver
and every completed property call, including a missing-call-table refusal.
Existing single-field and counted-length projections keep their route.

Computed scalar reads use the ordinary retained call operation throughout
Flow/Core/CFG/SSA/LLVM. Semantic Flow creates the normal call-scoped loan and
containing-owner guard for the actual receiver argument. Its independent
consumer verifies the property-to-accessor correspondence. No lexical owner
root is supplied by property syntax or Class layout admission. Getter source
coverage requires its concrete function, which must pass the normal body and
ownership consumers. No public ABI or generic-instance ceiling is changed.

The all-182-production-module and observer C0 frontend checks pass. The initial
checks retain two rejected temporary containing-object borrow expressions,
corrected by computing their scalar IDs before borrowing the relevant field.
The combined tracked fixture uses distinct results 19, 13 and 10 for its
arithmetic, child-property and method-call getters. Its two original-C0 ELFs
return 42 with clean unsuppressed Valgrind. The previous Astra host refuses it.
The new observer defines seven source, receiver and call-table controls.
Matching candidate execution and native qualification remain pending.

The source visibility walk also needs the accessor's original declaring Class
when its normalized function remains owned by the property symbol. The
successor checks that relationship through the actual getter source plan before
granting private-field access. The focused C0 observer check passes. The
earlier `795ac1f` build snapshot is retained separately.

That earlier observer subsequently passes the method-call getter through Flow
and all seven getter controls. Its arithmetic and child-property getters fail
with the literal private-field diagnostic. Those failures remain attached to
`795ac1f`. The declaring-Class visibility successor is a separate build.

## Direct finalizer physical consumer candidate

The frozen `bd06bf8` native host passes the pointer constructor, record arrays,
both long paths, local record arrays, forward Vector, Class memory, flat values
and slot checks. The genuine 256-instance and nested-constructor sources produce
real O0/O2 objects and linked exit42 ELFs with clean unsuppressed Valgrind.
The genuine 257-instance refusal remains. Its original-source attempts still
stop at the `CfgProgram` Class declaration.

The ordinary 262-member native attempt initially fails its test's count of
private functions. The source `main` has public C calling convention zero.
The separate `ordinary-methods-nativegen12-supplement1-O0` receipt counts
262 private members plus that entry, then verifies actual O0/O2 objects,
linkage, exit42 and clean memory. The original failed receipt stays unchanged.

The original hosted `FileHandle` case reaches SSA and passes LLVM verification,
then retains the physical-contract refusal. Read-only diagnosis captures the
actual LLVM module through the LLVM print API and watches the natural verifier
outputs. The Class-helper consumer returns false before the global body
consumer runs. Its finalizer lookup still searches only the generic table,
while the emitter uses the real direct source plan. The candidate adds that
direct entry to the independent unique-callee check and retains the generic
search, function-table bounds, calling convention and actual instruction checks.
Its all-production C0 frontend check passes. Matching native qualification,
including descriptor cleanup and finalizer mutations, remains pending.

## Match source copying and constructor Shared locals candidate

The frozen `5b4f8ca` observer passes all 20 focused cases, including four
computed-getter shapes with seven restored controls each. Its full 190-input
original-source attempt stops while copying `BindingIndex.schedule_children`
at the original `match` statement. Both Typecore and Flow attempts retain that
literal source-copy failure.

The generator now includes MatchStatement, EnumArm and EnumBinding payloads.
The copier follows the actual scrutinee, arm, binding and body edges. Its
separate generated consumer compares those edges and the original tokens.
A named-payload method fixture executes to 42 under original C0 at O0/O2,
with clean unsuppressed Valgrind. The earlier observer refuses its body copy.
Six copied-edge/token mutations have been added to the focused observer and
await matching execution.

Constructor source checks now admit initialized owned Shared locals produced
by the actual `shared_acquire` and `shared_clone` operations. They verify the
canonical Shared/Class types, explicit acquisition move, conditional use flags,
real source accessibility and current initialization state. Existing independent
owner and memory consumers still qualify acquisition, movement and retirement.
The unchanged original ClassStoragePlan constructor and TypeOwner fragments
execute to 42 with original C0 at both profiles and clean unsuppressed Valgrind.
The previous native host preserves its refusal and output sentinel. Five local
initialization transitions and three source mutations await matching execution.

The unchanged formatter uses the restored exact pinned Python 3.15.0 executable,
SHA-256 `8f9b3657aa73659bdee8d4ff9da604fba390870be227a8c626029c2402cb063c`,
inside a read-only task capsule. The Fedora Koji packages have valid header and
payload digests with no OpenPGP signatures. The executable matches the existing
repository hash, and the extracted dependency bytes have a separate inventory.
Installed Python, formatter pins and workflow scripts retain their identities.
The seven selected source guards, generator consistency check and both
development entries' all-source C0 frontend checks pass.
Full-original native qualification remains zero of two profiles.

## Direct source symbol-map capacity candidate

The matching `2314de0` observer passes all 24 focused cases. These include the
original ClassStoragePlan constructor through Flow and all eight restored
initialization/source controls, plus six match-copy controls. Its original
190-input Typecore and Flow attempts both fail with `ordinary member source map
resource limit` at the original SyntaxArena `replace_return_statement` method,
bytes 141383–141677. The observations take 77.98 and 78.10 seconds. Its C0
observer build takes 1,454.15 seconds.

The existing symbol window reserves every ID between the first and last source
symbol. Collection of declaration heads and later body locals can leave large
unrelated gaps in that interval. The candidate gives direct source methods an
ordered key table containing the actual original source IDs and a binary-search
lookup. Its independent consumer reconstructs the complete ordered domain from
Binder nodes and checks every source and concrete mapping. Genuine generic
plans use the existing dense intervals, including the offsets consumed by the
protected historical mutation and reference observers. The consumer checks the
storage role against the plan's actual generic/direct disposition. The 256
instance, 8,000,000 map-entry and 8,000,000 SSA ceilings are enforced.

A focused method-head/parameter/local witness executes to 42 with original C0
at both profiles and clean unsuppressed Valgrind. The previous source observer
passes that small witness through Flow. Six key-domain mutations and one
concrete-mapping mutation await execution with the new representation. The next
observer also records actual map usage on both success and refusal.

The separate constructor candidate verifies reads through actual borrowed or
owned Class parameters and initialized Class locals, including nested declared
fields. It checks the function-owned root, flags, visibility, exact field type
and each parent projection. Existing field/owner consumers reconstruct the
runtime storage and lifetime authority. A borrowed/owned/nested Shared clone
fixture passes C0 O0/O2 and clean unsuppressed Valgrind. The frozen `2314de0`
observer preserves its constructor refusal. Four root/type/visibility mutations
await matching execution. The first frontend check found overlapping temporary
borrows in the new control code. Separate locals correct those expressions,
and both corrected frontend entries pass.

The independent gen12 audit binds 195 consumed Git inputs, 46 tools, 88 native
artifact references and 27 clean memory streams, retaining the raw ordinary
count failure and separate passing supplement. Four earlier source observers
are independently rebound to 107/107/109/109 consumed Git inputs and their raw
outcomes. Their first audit attempt refuses upgraded host tool hashes. The
corrected audit uses the authenticated original tool capsule.

## Original enum channels and rebuild strategy observations

A whole-original C0 syntax survey covers 190 sources and finds seven enum
declarations with 250 payload-free variants. Exact original declarations plus
a focused usage entry pass C0 O0/O2, LLVM generation and clean unsuppressed
Valgrind. The earlier native host refuses the enum-returning function in Flow.
C0's O0 definitions use a leading caller-provided sum-result pointer and
`void` return for these results. Their memory shape is `{ i32, [0 x i8] }`,
size/alignment 4. Enum parameters use pointers to copied sum storage. Source,
Flow, sum transport, match control flow and independent physical qualification
remain required work.

Two simultaneous C0 jobs each use one thread at approximately one full CPU.
The measured host has 32 logical CPUs and about 51 GiB available memory.
The unchanged CLI exposes no parallel-build flag. A native-module build probe
passes source semantics and refuses the enum-result channel needed at the
proposed partition. The first probe's invalid namespace wrapper is preserved
separately. Existing matched gen12 Core generation takes 67.70 seconds against
its 3,111.53-second complete native development build. The additional cost lies
after Core. Userspace `perf` sampling is refused by host access controls, with
the raw refusal retained. These observations establish no rebuild speedup.

## Core work and LLVM traversal candidate

The previous O0 host admits both long-path fixtures to Flow and refuses them in
Core. The sequential assignment fixture has 5,127 Flow nodes and the ordinary
call fixture has 3,850. Original C0 executes both to 42 with clean memory. Both
old refusals preserve their sentinels. The Core consumer now scans for unique
consumers only for owning values. The producer and consumer skip abort-pair
searches when a call argument has no preceding move reservation. The existing
ownership checks and work ceiling still apply.

The SSA verifier reconstructs immediate dominators from the independently
checked CFG and answers queries using dominator tree intervals. LLVM emission
uses a bounded stack with the former next-before-other traversal order. The
exact-source kernel in `ssa-dominance-kernel2` matches six normalized production
declarations. At both O0 and O2, the independent reachability and traversal
oracles cover 15,002 small graphs, 237,409 dominance queries, disjoint functions,
budget refusals, and the 8,192-block chain. The chain and its 2,048 queries use
100,349 SSA work steps. All four memory runs are clean. The existing declaration
lookup kernel also retains its 5,468 verified cases per profile. These kernel
tests and `native-longpathcheck1-O0` establish focused checks. The integrated
`64ca46e` O0 host takes 50:37.65 to build at 2,290,888 KiB peak RSS. Both long
paths now produce verified LLVM, relocatable ELF objects and native executables.
The assignment and call cases emit 5,129 and 2,573 blocks, respectively, and
both execute to 42 with clean Valgrind. The audit also retains the unrelated
record-array refusal and rechecks 195 Git-bound inputs and 46 tool identities.
`native-gen8-independent-audit.json` has SHA-256
`c2bda8ec825491d39e51c65f3bd8654640e8bfa19babd4d04e33050f2c7e8fae`.

A read-only stack sample of the in-flight frozen C0 build found bootstrap SSA
owned-field loan verification during LLVM lowering. The sample identifies the
active phase at that instant. It does not measure how much of the total build
time that phase consumes.

## Hosted-files Error and Class finalizer candidate

The exact original `files.astra` plus client runs under C0 at O0 and O2. The
prior Astra observer refuses the `FileError` declaration at bytes 840–1169.
The candidate admits copied scalar getters on derived Error payloads and
independently verifies their bound source field and result in the layout check.
The private Error header and native result convention stay unchanged.

For a fielded ordinary Class, the candidate verifies the source `deinit` body
as a private void function with the concrete borrowed receiver. The LLVM drop
helper calls it after the null guard and before field retirement. The physical
consumer binds the exact source-derived function, receiver operand, call
convention and instruction order. `original-file-handle-baseline3` uses the
unmodified hosted-files library and exercises normal and throwing cleanup after
opening an actual file. Both C0 profiles exit 42 with clean memory and zero
leaked descriptors. The first fixture attempt retains its parser refusal, and
the second retains the raw Valgrind output that used `inherited` in its descriptor
summary. The finalizer source-binding check and complete C0 semantic run pass
in 53.88 seconds at 360,404 KiB peak RSS. Integrated Astra qualification is
pending.

## Original compiler module object candidate

The exact original production population has no `main`. The independent C0
`library-object-baseline2` accepts a function-only source and produces verified
LLVM and native objects at both profiles. Its O2 object has no defined source
function after dead-code elimination. The earlier Astra executable route
refuses that same source with status 1 and preserves the destination.

The explicit `--native-module` development route requires zero source entry
points. The ordinary route continues to require exactly one. Every admitted
source function in module mode is retained in an ordered `llvm.used` table.
The mechanical C shim constructs the table from passed LLVM functions. The
independent Astra consumer checks its exact entries, module, private linkage,
pointer types, array length, section and appending linkage. This introduces no
source-name selection or owner authority.

`library-roots-kernel3` executes the actual consumer and C shim at O0 and O2.
Both private functions remain in the optimized native object. Its symbol table
has no exports. The unused third fixture function disappears at O2. Six
LLVM-valid negative cases exercise missing, reordered, extra, substituted,
wrong-section and wrong-linkage roots. Unsuppressed Valgrind passes after
explicit module-context destruction and LLVM shutdown. The first fixture
retains its deprecated global-context API build failure. The second retains
its real context leak. The complete C0 semantic check initially refused a
projected flag write. Routing that write through the actual field owner's
method passes in 53.81 seconds. Full candidate module integration is pending.

Source review also found that the recursive Class-field admission query still
rejected the canonical non-owning `void*` type after its separate layout
consumer admitted it. The query now uses the same canonical pointer predicate.
The frozen earlier opaque observer retains its original source and outcome.

The observer also has explicit `--obligations` and `--module-flow` modes. The
first reports every Class and every refused runtime-function source predicate,
with original source spans, using one checked input population. It provides
diagnosis only. The second applies the explicit zero-entry Flow mode. Both
avoid treating a first refusal as a complete source assessment. Full source
and object qualification still require their independent downstream consumers.

## Per-function capacity and verifier work candidate

`module-unit-baseline2` exercises the former aggregate limit with two actual
source programs. The 19-function program has 160 assignments in each of 18
units. The single large function has 2,100 assignments. Original C0 executes
both programs to 42 with clean unsuppressed Valgrind at O0 and O2. The frozen
`119829c` Astra host refuses both with `RECOVER_FLOW 2 0 8192`, preserving both
destinations. The first fixture attempt remains recorded with its missing
assertion declaration diagnostic.

The candidate counts Flow nodes, Flow edges and CFG blocks within each
function. Each consumer reconstructs those counts from its verified population.
Aggregate storage grows on demand under the existing SSA budget. The 8,192
per-function bound, 256 generic-instance bound and 8,000,000 SSA work ceiling
apply. The exact-source `module-capacity-kernel3` exercises 16,384 rows across
two units, verifies cross-function separation, and refuses a single extra row,
a cross-unit Flow edge and insufficient SSA work. Both O0 and O2 execute to 42
with clean Valgrind. The first two kernel attempts retain their declaration
count and missing diagnostics provider failures. The successful receipt
SHA-256 is `383c40167080628d63b6938b61112a2db24cef3678adc5f1f4b8c00c5e5837f9`.

Core records owner uses while visiting their consuming operations. The Core
consumer independently reconstructs immediate parents, resolves parentheses,
and checks the actual use, reservation and slot. SSA indexes reservations once
and explores each slot over the blocks of its own function. Incoming Error phi
edges are indexed from verified CFG edges. `ssa-owner-index-kernel2` compares
the old and new slot traversal on eight controls and 2,048 interleaved functions
with 8,192 blocks. It records 4,202,496 prior and 26,624 candidate metered steps
on that fixture, with exit 42 and clean Valgrind at both profiles. The receipt
SHA-256 is `c861e861c37127ec313ff50f5272c5b529b19e70ad4db43f4cc8563848ffa6ec`.

The generic consumer walks every slot in each independently bounded map window.
Flow and CFG retain the complete generic verification at their pass boundaries
and read concrete call and receiver facts at each use. The all-module C0
semantic check `native-moduleunitscheck1-O0` passes in 53.51 seconds at 360,604
KiB peak RSS. The kernel measurements establish bounded behavior on their
fixtures. Native integration and matched complete-original timing are pending.

The frozen `2242bb9` O0 candidate now passes the actual 19-function program
through Flow, Core, CFG, SSA, LLVM verification, optimization, object emission,
linking, execution and clean unsuppressed Valgrind. It has 11,749 LLVM blocks.
The single oversized function is refused at 8,192 Flow nodes and preserves its
destination. The same candidate executes the original focused `Vector` client
to 42 with clean Valgrind. Its complete-original attempt retains the earlier
`Vector` refusal. Its array probe retains the earlier physical-contract refusal.
The raw overall focused sequence has two failed steps. Separate Class-memory,
flat-record and owner-slot steps pass. The C0-produced test host build takes
50 minutes 23.89 seconds and 2,295,416 KiB peak RSS. The original complete
compiler native profiles proved remain 0/2.

`native-gen9-independent-audit.json` rechecks 195 consumed archived Git inputs,
all 46 tool identities, the five focused result sets and their raw command
streams. It independently binds the x86-64 ELF, LLVM and object hashes, clean
memory receipts and preserved refusal sentinels. Its five result sets have
2/2/2/2/3 native positives and 1/2/0/0/5 sentinel-preserving refusals. The two
library-kernel Astra declarations also match the actual source AST exactly.

## Earlier progress snapshot — 2026-11-10, candidate4 and template work

| Work item | Evidence-backed state |
|---|---|
| Independent R5 post-delivery G12 | Complete; separate fresh verification described below |
| Original compiler C0 front end | All 180 compiler files plus 10 dependencies pass together |
| Bounded O0/O2 regression checkpoint | Qualified at c99a96a with the disclosed failed raw jobs and separate supplements; does not qualify later edits |
| New owning-Class slot runtime helpers | O0/O2 native, C ABI, cleanup-order and unsuppressed memory checks pass; 10 physical graphs, 24 LLVM-valid mutations and 20 convention controls |
| Slot source/owner/Core/CFG/SSA/LLVM integration | Three focused O0 source programs pass all stages, actual native linkage/execution and independent artifact/memory checks at4f797d9 |
| Candidate4 O0 host rebuild | Finished in53:07.61, peak RSS2,532,892 KiB; no compiler completeness inference |
| Focused source-to-native slot checks | Empty field slots, reserve/append/take and all six operations pass; five additional owner/source negatives refuse with preserved destinations |
| Original generic Bag source | All seven original members and small Bag<Item> Flow pass in the repaired observer; whole-original population still refuses concrete collection admission |
| SSA local-declaration lookup | Exact new kernel passes C0 O0/O2 occurrence, boundary and memory checks; integrated Astra SSA validation is pending |
| Current O2 host rebuild and broad regressions | Deferred until focused O0 integration succeeds |
| Full original compiler native objects | 0 of 2 profiles proved; remains a completeness blocker |
| Full compiler linkage and performance | Unproved |
| Milestone26 delivery and its post-delivery check | Not published or run yet |
| Milestone27 self-hosting | Outside this authorization |

Every completion claim is tied to a source/compiler identity and an actual
receipt. Failed attempts remain failed. The earlier approximate30% estimate
was an engineering estimate, not a measured fraction of language support;
the states and counts above are the progress authority. The later approximate35%
estimate is likewise an engineering estimate, not measured language coverage.
The next decision is bounded generic-template source proof and concrete Flow,
followed by the still-unproved full original source frontier.

Candidate3's 6,180,656-byte O0 ELF has SHA-256
`a6d2600448ffeed973824faba11c7093ab2138bd5149123193e9e004a598eb12`.
The empty-field-slot source passes actual Flow/Core/CFG/SSA and preserves the
output sentinel when native emission exits5 with `LLVM_INVALID_IR: recover
physical contract`. The full field-slot program and six-operation variant
are C0-valid and instead fail Flow at slot call statements. Original generic
Bag still stops at its declaration. These failed receipts are unchanged.

An exact source-order-matched C0 Core map takes73.49 seconds. The unchanged
candidate is then observed with read-only debugger breakpoints: LLVM's verifier
returns0, while the independent physical consumer returns false. The dumped
module is a diagnosis witness only and is never linked or executed. The new
empty-slot predicate incorrectly required a null operation, although emission
records its actual branch; the correction requires that exact terminator while
retaining the constant/type and one-instruction checks. The independent Flow
statement consumer also needs to recognize its already-verified slot-call
operation69. The stage diagnostic's genuine success exit is42; the focused
harness now checks42 rather than0.

Candidate4 at4f797d9 includes those two corrections. Its O0 host SHA-256 is
`2d4214a24e4471bc04bcf5c1d16906bca599a6d11f8218d243efbd5e3d8d9cc2`.
The three positive source probes each pass actual Astra LLVM verification,
optimization, object emission, ELF linkage and exit42. Independent C0 executions
match stdout/stderr; all six C0/Astra unsuppressed Valgrind receipts have zero
errors and zero remaining allocations. The six-operation probe exercises reserve,
append, take, replace, count and capacity. Five C0-invalid ownership/source probes
are also refused by Astra without replacing the output sentinel.

`compiler-complete26v4/repair4-independent-audit.json` independently binds the
348 source and46 tool inputs, raw/optimized LLVM, objects, C0/Astra ELF identities,
ELF64 x86-64 headers, command exits and raw memory logs. Three live WIP source
differences are authenticated against4f797d9, rather than called rebuilt. The
empty-source LLVM is byte-identical to candidate3's earlier refused diagnostic;
only the correctly repaired consumer admits it now. The earlier refusal remains
failed. This is focused O0 source qualification only: no current O2, inherited
340/71, generic Bag, whole compiler or Stage1 credit.

The actual original Bag plus client remains C0-valid, exit42 and clean memory,
while candidate4 refuses at Flow's generic declaration boundary. The new bounded
template proof checks every original constructor/member, including unused methods,
and all actual concrete instances still need ordinary independent Flow, owner,
Core, CFG and SSA verification. Lexical `this` only selects a source declaration;
it supplies no runtime root and does not change CheckedIndex.add_signature's
independent owner-root deferral. A smaller current Typecore/Flow observer is being
built for diagnosis before another full native host build. It emits no target
LLVM or objects and receives no native completeness credit. The current190-input
C0 semantic check passes in48.92 seconds; the focused observer's C0 semantic check
also passes. These are front-end checks, not execution of the new template proof.

The focused template observer retains113 source inputs and46 tool inputs; a
separate during-build audit matches every byte. Three actual C0 native oracles
(original Bag, renamed Vault, and a Vault with an unused arithmetic method)
all exit42 with unsuppressed zero-error/zero-leak memory receipts. Their nine
commands take1.13 seconds combined. Astra template/Flow results remain pending.

The first template observer builds in1369.36 seconds, ELF SHA-256
`bb8e928ea0f98fa4eb3ed1b3d35eee5275255a2d514051331dae84c5dc9c239c`.
Every focused observation then terminates with SIGILL before printing a template
result. These receipts remain failed. The conditional full native build is
explicitly skipped. Read-only GDB and a source-order-exact C0 Core map trace the
trap through `recover_template_value` to SyntaxArena's guarded identifier getter,
line6460. The new checker requested a Name-only accessor from a Move node before
selecting the Move accessor. The corrected source selects the node-appropriate
accessor before invoking it. Its native rebuild and functional checks are pending;
neither the trap nor the correction establishes generic Bag admission.

The repaired immutable observer atb43a946 builds in1368.14 seconds, ELF SHA-256
`a3f877c77b7da6c7c4b0248b23327f8322c455de34d8f0aeb462a96a36d2329d`.
`template-cases-proof2` passes: the actual original Bag and renamed Vault each
report all seven original members accepted, actual Flow exit42, and four source
mutation controls with restored valid twins. The C0-valid unused arithmetic
method is explicitly refused by both template and Flow consumers. C0 oracles
are reused with disclosed byte/hash bindings, not called freshly executed.
These are Typecore/Flow observations under a C0-built host; Core/CFG/SSA/LLVM
and native Bag target execution are still pending.

`original-flow-proof2` authenticates all190 read-only original inputs again
against the exact initial Git commit. One actual whole-original run takes131.18
seconds and exits2: `FLOW 3 307096 0` at the same original Bag declaration.
All seven Bag members separately report SOURCE1 while the complete template
reports SOURCE0, whose predicate also requires every actual concrete instance's
storage admission. Vector's constructor, ensure and append report SOURCE0.
The whole compiler remains unadmitted; this source family is not a substitute
for original Bag<FlowGraph> payload support or the independent graph55 owner
proof. A new native O0 probe freezes every production module atf818ab6 before
building; its output and focused native results are pending.

That O0 probe finishes in51:00.52, peak RSS2,254,972 KiB; its ELF SHA-256 is
`39d189ff56b35997ce80f44d5ad0e35231de959d0647555a0f97afea43b9cd54`.
Its smaller entry retains193 Astra inputs including all180 production modules;
the differing source set prevents a matched cold-speedup claim. Empty slots and
all six ordinary field-slot operations pass actual native execution and memory
checks. Their raw LLVM and final ELF identities match the preceding candidate4
results, although optimized textual LLVM keeps its actual differing path bytes.
The five additional invalid sources still refuse; four negatives skipped by the
first fail-fast sequence run separately as `slots-nativegen2neg-O0`.

Original Bag's six-operation program passes actual Flow/Core/CFG/SSA but still
exits5 at physical validation and preserves its output sentinel. An exact C0 Core
symbol map takes65.61 seconds. Unchanged-ELF GDB traces LLVM verification0 and
`recover_error_types_verified` false: original generic Bag is symbol1/type17,
while its closed instance is symbol44/type34. The Error-table consumer demands
an ordinary runtime layout even for the independently checked template definition.
The correction permits only the complete template source/closed-instance proof
and retains all four null-cache requirements. Four planned cache-model mutations
keep LLVM valid and must each refuse, with restored valid twins. These are not
new physical IR mutation categories. Both the correction and controls pass C0
front-end checks; their new native build/execution remains pending. The earlier
refused module is a diagnosis witness only and is never linked or executed.

The next record-storage work uses fresh original-C0 evidence rather than assuming
one representation. `record-abi-actual1` executes normal and checked success/error
paths at O0/O2, exit42, with unsuppressed zero-error/zero-leak memory receipts.
The alignment-sensitive nested record has a nested memory representation, while
native arguments, ordinary results and checked success storage flatten its four
scalar leaves. Exact signatures are `ptr(ptr,i8,i8,i64,i8,i32)` for the checked
free function and `{i8,i8,i64,i8}(ptr)` for its Class getter. LLVM verification and
ELF64 x86-64 headers are checked. These original-C0 receipts do not qualify Astra
record admission or native generation. Early invalid cast/hexadecimal spellings
and formatter refusals remain separately preserved; the passing fixture uses
the accepted decimal spelling.

Static original C0 AST receipt159 also records186 private fields,727 methods and
three properties in SyntaxArena. The current Class-storage source domain has a
128-field restriction, and ordinary eligible members currently use the generic
instantiation route. Those additional large-source issues require proper field
layout and ordinary nongeneric member planning; increasing the256-instance ceiling
does not close them. This is source-policy inspection, not a claim to have reached
or passed that Class through the native pipeline. Graph55's owner-root deferral
and the8,000,000 SSA ceiling remain unchanged.

A candidate record source plan now records the original field-parent tree and
the separate flattened leaf order. Its consumer independently reconstructs source
parentage, every field ordinal, subtree counts, leaf coverage and TypeOwner identity;
it does not invoke the producer or trust its counts. The plan remains unhooked
from native admission: memory packing/unpacking and flattened carrier lowering
must still be implemented and independently proved. Its C0 front-end check passes;
native source-plan and seven mutation-control checks are pending. The earlier
observer shared-swap and missing Error-bound prechecks remain failed receipts.

The immutable source-plan observer at5b870dd subsequently builds in1447.82
seconds and exits42 on the real record ABI fixture. RecordLeaf has three plan
parts/two leaves; RecordPair has six parts/four leaves with paths0,1.0,1.1,2 and
widths8,8,64,8. Seven independent corruptions per record are rejected and every
restored twin is accepted, including a distinct TypeOwner identity.

The candidate LLVM memory/value helper class and its independent consumer are
also exact production-AST-bound in `record-runtime-actual2`. The consumer walks
the physical nested memory tree independently of emitter path metadata. Load
and store helpers preserve the32-byte nested memory and24-byte flat carrier
layouts. Ten LLVM-valid path/value/alignment/volatile/convention mutations refuse
with restored valid twins. Actual O0/O2 objects and linked executables exit42,
preserve all padding bytes checked by an independent C observer, and have clean
unsuppressed Valgrind. Those focused commands take1.86 seconds combined. A first
kernel attempt lacks a required existing C API declaration and remains failed.
All180 current production modules pass C0 front-end checking after the helpers.
This helper and source-plan evidence alone does not qualify Astra record
admission. The memory helper remains unhooked; the subsequent value integration
below must pass its own native and independent whole-module checks.

The frozen `3881177` native O0 host completes in3,101.18 seconds and has SHA-256
`177e9213d52aaa793273dc2ea8bc396907b0cbe004788f6e3ba4b1374f47b67f`.
`native-gen3-work.json` records successful template cache controls (exit42) and
the complete focused slot sequence. `slots-nativegen3-O0` independently executes
three C0/Astra positive programs to42 with clean unsuppressed Valgrind and five
negative refusals with preserved output sentinels. The new passing original
generic Bag program retains the exact original Bag file and exercises all six
slot operations. Its Astra LLVM SHA-256 is
`a9158fef0dc5c9e11422400a90bf47b70298385856cd1a7b5e97a7d50a0c89fd`
and linked ELF SHA-256 is
`cad5be6561ad434d8d8a8d42ead9287b2572e8a027edf01e1109ee2597ec58d8`.
The independent follow-up rehashes the actual positive ELF files and reads their
raw execution and Valgrind receipts. This closes the focused generic-template
physical-cache failure; the earlier gen2 failure remains unchanged. No O2,
inherited340/71 or complete original compiler qualification follows. Full original
compiler native profiles proved remain0/2, and graph55 remains deferred.

The next candidate retains an evaluated record aggregate as a real Flow child
for `make().field` and `object.method().field`. Independent source checking binds
that child to the exact aggregate expression and field declaration; SSA checks
its dominance without inventing a lexical owner root. The existing direct local
record path is retained. The LLVM emitter and consumer select the child value
for this new form. This is limited to the already admitted flat copyable records;
it does not enable nested record memory or the deferred graph55 receiver proof.
`native-recordvaluescheck1-O0` passes C0 semantic checking of all180 production
modules and the focused host in52.40 seconds. `record-values-oracle1-O0` has two
fresh original-C0 exit42 and clean unsuppressed memory receipts, for the source
fixture and its renamed equivalent. They exercise once-only receiver mutation,
normal/checked record results and the error edge. These initial C0 receipts
supply no Astra native or complete-compiler credit.

The subsequent frozen `c8cdccc` O0 host completes in2,882.73 seconds, reaches
2,230,896KiB maximum RSS and has SHA-256
`6c6f9afa28dcce2ba9055f29b75380aa639ef9546e4fdaede36156b9f5fe8ea0`.
`record-values-nativegen4-O0` then passes source-stage and restored source/LLVM
controls plus actual native generation, execution42 and clean unsuppressed
Valgrind for both the original and renamed fixture. `slots-nativegen4-O0`
retains all three focused positives and five refusals. The separate
`native-gen4-independent-audit.json` reauthenticates195 consumed archived inputs
against that Git revision, all180 production modules, actual tool identities in
the original23.1.4 capsule, both sets of raw command stream hashes, ELF64 x86-64
products, execution and memory receipts. This is an independent receipt recheck,
not a new target execution. The observed build cost is not a matched speedup.
These are O0 focused results; O2, inherited340/71 and whole original compiler
qualification remain unproved for this host.

The current nested-value candidate uses the independently verified source shape
to produce flattened native carriers, parameter groups, constructors and field
projections. Separate consumer traversals reconstruct scalar leaf counts, types
and offsets from the actual source declarations without reading producer shape
offsets. The physical consumer verifies each insert/extract, its block and exact
instruction inventory, including partial LLVM constant folding. Already admitted
flat records retain their emitted carrier shape. Class memory remains refused;
an explicit Error-field guard also prevents native-value admission from silently
flattening nested record memory. The original Error header and E25-A-v1 remain
unchanged. `native-nestedvaluescheck2-O0` checks all180 modules and the focused
host through original C0 semantics in49.80 seconds. `record-values-nestedoracle2-O0`
has four original-C0 execution42 and clean memory receipts: nested values, their
renamed equivalent, and Class/Error nested memory that the candidate must refuse.
Nested Astra stage/physical/native results are pending the next frozen build;
these C0-only observations receive zero Astra native or complete-compiler credit.
The256 generic and8,000,000 SSA ceilings and graph55 deferral remain unchanged.

While that rebuild uses frozen inputs, the SSA consumer's repeated whole-Core
local-declaration scans are replaced with one local index reconstructed from the
independently verified Core/CFG. Missing and duplicate sites still refuse, and
the original per-use dominance checks remain. Each index scan step is metered
under the unchanged8,000,000 budget; no cached producer index is trusted.
The byte-exact production kernel and RecoverWork declaration are independently
bound by C0 normalized ASTs. Using minimal field containers, an occurrence oracle
checks5,461 exhaustive cases and seven capacity/order cases per profile under
C0 O0/O2. Both actual native executables exit42 with unsuppressed zero-error/
zero-leak Valgrind; all commands take1.38 seconds combined. The8,192-row case
uses exactly8,192 index steps. The former full scan for8,192 reads would visit
67,108,864 rows; this is an algorithmic count, not a measured whole-compiler
speedup. Initial harness AST-selection and parameter-assignment failures remain
preserved; the passing receipt is `ssa-index-kernel3`.
All180 current production modules also pass the focused C0 front-end check after
the SSA edit. Integrated SSA/Astra native, whole-compiler scaling and performance
remain unproved; these helper containers receive no compiler completeness credit.

A separate focused native test entry compiles with every one of the180 current
production compiler modules under C0's actual `--dump-semantics` command. Its
native build and target execution remain unproved. Historical mutation dispatch
is excluded from this development host only; target source is never pruned and
no inherited regression qualification transfers to it. An explicit `--snapshot`
route freezes Git-authenticated source bytes read-only in the task runtime,
allowing later live engineering without changing an active build's inputs.
This is a build-input archive, not another checkout or a toolchain replacement.
No speedup follows from either the smaller test entry or a front-end check.

`original-source-candidate3b` independently replays all190 frozen,
read-only original inputs: exit3, `RECOVER_FLOW 3 307096 0`, preserved sentinel,
127.70 seconds. The two subsequent corrections are explicitly not compiled
into that observed product. This refused attempt does not demonstrate full
compiler performance or a speedup. A first outer-harness check encountered
the externally upgraded host LLVM before entering the capsule and stopped
before launching the compiler; that harness failure is retained separately.

The existing checkout started clean at commit
`8b8cf003ea0b47b1322b887317b6fc535bfb9850`, tree
`fe0644c1b2e2d5db3d97b898933bc24166f034e2`.

## Intake and predecessor

R5 post-delivery G12 was independently closed before milestone26 implementation.
The actual canonical report is 26,132,976 bytes, SHA-256
`69a1f817f1448ab8eed5cac5db8f6f8e7d262385a9c0b959a8750f573bfeb2a9`.
All 188 payloads, 152 patch/Git/live source snapshots, 15 segments and the
25,381,260-byte transport hash match. Independent verify-only restoration checks
all 229,485 logical rows. All 1,044 proof hashes, 451 protected paths, 6,622 donor
files, original approval, hooks, settings and installed workflow identities match.
Fresh C0/Astra O0/O2 replay of four R5 cases per profile reproduces the exact raw
LLVM and C0/Astra ELF hashes with unsuppressed zero-error/zero-leak Valgrind.
The original ABI observer again checks nine mutations for each of two receivers.
All 340 inherited and 71 new identities/profile were separately rebound to
their source/IR/ELF/command/memory receipts; this is not fresh execution of 411.

The exact original milestone26 submission remains unchanged:
`43c89a44a04912f3fdefa4f4c73380095874301eea44cb5684ff0406368e2b11`,
1,390,103 bytes. Its 279 members exceed the unchanged installed intake's
256-member limit. Both `--check` and `--prepare` genuinely refused it.

The user subsequently authorized continuing and explicitly selected a lossless
compatibility packet. That packet embeds the original ZIP byte-for-byte,
preserves TASK.md and every substantive task document, and uses the same Git
base. Its SHA-256 is
`c2471bf201cf558a4c079d7b185ffb17454322366743e1719289232639f8558b`,
1,385,693 bytes, 14 members, filename
`ASTRA-SELFHOST-COMPILER-COMPLETE-26-COMPAT-SUBMISSION.zip`.
Installed native `--check` and `--prepare` both accepted this packet. No skill,
script, limit, toolchain pin or original packet was edited. Exact predecessor
staging and the R5 ZIP were preserved before normal intake retired its staging.

## Full original population and observed refusal

The original Git tree contains 180 Astra compiler files. Every one is included;
none is replaced with an observer, a reduced view or a C0-generated program.
The existing authored compiler recipe names ten library dependencies. Thirty
other library files are inventoried separately with their exclusion reason;
they are not counted as compiler dependencies or translated code.

The complete 190-file input has 1,926 top-level C0 syntax declarations. Every
file was independently parsed by the exact C0. An initial whole-context
C0 invocation incorrectly
combined `-O0/-O2` with `--check` and was refused as a command error. The corrected
whole-context check timed out at 180 seconds. A second corrected check on frozen,
read-only original inputs reached its 2,400-second process-group deadline and
was killed with exit-9; its stdout/stderr contain no semantic diagnostic. The
whole process group, including GNU time, was killed, so that attempt has no
completed GNU-time CPU/peak-RSS measurement. Sampled RSS is only a lower bound.
None of these attempts is a semantic PASS or a demonstrated semantic rejection.

The subsequent `original-C0-semantics1` check uses C0's actual front-end mode,
`--dump-semantics`, on all 190 frozen original inputs. It passes with exit0 in
48.66 seconds, peak RSS335,608 KiB, with no diagnostic. The earlier `--check`
mode proceeds through LLVM and was not a front-end-only check. Its failed and
timed-out receipts remain unchanged. Original C0 front-end admission is now
proved separately; native compiler generation through its later passes remains
unproved.

Both R5 native profiles, fed all 180 compiler originals and ten dependencies,
stop in Typecore at `lib/astra/collections/bag.astra:3`, bytes `[133,649)`,
fragment SHA-256
`c84e310c7adbe3cb865e7e0653109dd33ab524fa593511056bb5ff3dbecbb9f6`:
`generic syntax resource limit`. Both preserve an existing output sentinel.
Their independent class-storage ledgers agree byte-for-byte: 309,231 original
parsed nodes, 24,648 declarations, including actual generated
`<Utf8MessageFactory>` backing. A ledger type, zero use or successful syntax
parse never grants Flow/Core/CFG/SSA/LLVM acceptance.

`tests/selfhost-compiler-complete/run.py` records original Git blobs, live host
implementation hashes, exact C0 ASTs, full node spans/fragment hashes, actual
compiler identities, per-stage refusal and GNU time receipts. Subsequent runs
freeze original Git bytes read-only as target data, so implementation fixes
cannot silently replace the original compiler being tested. The source inventory
does not yet establish every cross-module dependency edge or semantic disposition.

## Generic syntax budget correction

The previous copier compared the complete parsed arena with 262,144. The full
original program already exceeds that count before any specialization is copied.
The correction budgets **additional generated syntax** rather than unrelated
original declarations. It retains a global 262,144-generated-node quota, the
256-instance ceiling, depth128 and all existing map bounds. It does not raise
the 8,000,000 SSA-step ceiling or the separate 1,024-block SSA guard.

The producer checks room again immediately before each generated node allocation,
including auxiliary hidden-receiver type/parameter and receiver-expression
nodes. This prevents recursive unwinding or receiver scaffolding from allocating
past the quota. Already-cached nodes require no new allocation. Failures stop
signature/call publication. The separate consumer checks the inclusive final
generated-node count without calling the producer predicate. Original roots,
type IDs, instance keys and structural substitution verification remain separate.

The exact two production scalar predicates execute under C0 and R5 Astra at
both O0/O2 on 49 independently derived boundary pairs. These include the real
309,231-original-node count, quota endpoints, negative/backward counters and
signed-integer limits. Three actual semantic mutants (producer off-by-one,
consumer off-by-one and counting original nodes again) compile to LLVM-valid
native ELFs and fail the oracle at both profiles; positives exit42 with clean
unsuppressed Valgrind. These are **helper-only** source tests, not full generic
cloning, new whole-module physical-mutation categories or whole-compiler PASS.
The generated copier's token check matches its authored generator.

The first cold O0/O2 build candidates were deliberately stopped after review
found the auxiliary receiver allocations. Their exact commands, source identities,
costs and stop/failure receipts remain preserved as stopped candidates. The v2
pair builds the complete corrected source in distinct external leaves. Reused
R5 translators are historical baseline products; neither a helper test nor a
warm reuse is described as a cold compiler build.

The v2 focused O0 stage observer was genuinely rebuilt by C0 in 1,283.61 seconds
(1,274.60 user / 0.99 system seconds), peak RSS 1,550,232 KiB, product SHA-256
`7e1fc0ba3b5684976605163e2d2177cce289d57a8991cb1aebcd90ab3c051e0d`.
It checks the exact complete original population in 130.96 seconds, without
the previous Typecore resource failure. It then returns **exit2**, with
`SHARED_FLOW 3 307096`, binding that node to the same original Bag declaration
and fragment hash above. The wrapper's successful exit is not compiler PASS.
Its raw shared-use rows retain deferred19 obligations; reaching Flow does not
discharge them or admit the compiler as a whole.

The first Flow stop is the ordinary-Class declaration guard in
`recover_flow_lower`: the original `Bag<T>` is not qualified by the Error or
ordinary success-storage predicates. `recover_storage_fields` currently admits
scalar/text fields, numeric buffers and independently checked Class/shared
fields; it does not supply the original owning `T[slots]` Bag contract. Generic
template/concrete coverage, slot-owner operations, initialization, cleanup and
independent source/physical consumers must be proved together. Skipping the
template, pruning Bag or treating layout admission as a receiver root would
not close this frontier. The focused observer emits no target LLVM or native
object and earns no full-original native execution credit.

The continuation now includes a module-local `RecoverSlotWriter`, derived from
the original five slot operations: reserve, append, take with compaction and
vacating, replace with retirement, and reverse drop with descriptor clearing.
Its LLVM handles have the caller's module lifetime. The independent physical
consumer reads the actual instructions and edges; the legacy source wrapper
still requires calling convention zero. The physical consumer additionally
accepts an explicitly expected convention8 drop for the private Class runtime,
checking both declaration and call. This adds no public or checked-call carrier.

The focused `slot-runtime.py` recipe compiles the exact production writer,
cursor, physical body consumer and support declarations with the original C0.
Normalized C0 AST hashes bind each extracted declaration to production source.
Ten helper graphs pass the independent consumer; 24 LLVM-valid instruction
mutations and 20 wrong-convention controls are refused, then original graphs
are restored and rechecked. Real O0/O2 LLVM verification, object generation,
GCC C ABI linkage and native execution pass for both drop conventions. Four
native helper ELFs and two original-C0 Bag oracle ELFs return42 with the exact
cleanup trace `22,20,24` and clean unsuppressed Valgrind. The C observer asserts
the 16-byte, alignment8 descriptor and offsets0/8/12. Twenty-four fatal controls
trap and receive no returning-memory credit. These receipts are under
`compiler-complete26v3/slot-runtime-actual3`.

The first local-slot probe was rejected by C0 itself under BUFFER-1 and remains
a negative, with its failed harness receipt retained. Real field-slot and
original generic Bag positives run under C0 and remain refused by the prior
qualified Astra host. The new runtime helpers are not yet connected to
RecoverFlow/Core/CFG/SSA source admission; no rebuilt compiler, record-slot
element support, whole-module physical qualification or full compiler credit
is claimed from the focused helpers. The earlier bounded regression campaign
qualifies its recorded compiler checkpoint, not these unbuilt host edits.

The next implementation batch adds retained Flow operations68 (empty slots),
69 (slot call) and70 (count/capacity), with source correspondence, field-place
checks, unique owner consumption, entry reservations, CFG/SSA uses, module-local
helpers and physical instruction consumers. Slot descriptors remain fields;
the callable carrier rules are unchanged. Initialization requires the actual
owned field in its verified constructor; whole-descriptor replacement is
refused. Mutating calls require its existing writable field fact and preserve
the receiver during argument evaluation. Nested slot mutation during those
evaluations is conservatively refused until a separate alias proof exists.
No lexical root is synthesized. This batch is not yet native-qualified; full
compiler and template/concrete coverage remain unproved.

`current-C0-semantics4` checks all 190 current implementation inputs after
this batch: exit0 in50.22 seconds, with exact before/after source hashes.
This is a front-end check. The subsequent O0 integration build and focused
native field-slot probes are separate pending qualifications.

Four additional focused C0 source negatives cover duplicate transfer, missing
explicit move, a borrowed transfer and a nominally different slot element.
The original C0 rejects each; the prior qualified c99 host also refuses each
without overwriting the output sentinel. Exact diagnostics and recipe/source
witnesses are in `compiler-complete26v3/slots-negativebaseline1-O0`. This is a
baseline, not new-host qualification, and adds no credit to the inherited
15-array/6-owner ledger. An initial test-harness placement error, rejected by
argparse before any compilation, is preserved separately and is not a compiler
failure. The corrected test recipe also binds its exact bytes in each run.

The generic instantiator also traverses its declaration's original node/symbol
windows directly instead of rescanning unrelated original declarations. The
mapping functions are identically zero outside those windows; processing order
and mapping bodies are unchanged. The independent structural consumer still
walks the full original population. Boundary membership checks cover50,905
valid windows and2,419,250 selected ordinals, including the309,231-node original
program and signed-counter bounds. This is conditional source equivalence;
actual clone behavior, whole-module speed/RSS and full compiler performance
remain pending the rebuilt host. No generic or SSA ceiling is raised.

Both complete corrected C0-built hosts were subsequently fed the exact frozen
original 190-file population. Each returns exit3 with
`RECOVER_FLOW 3 307096 0`, at the same original Bag span and fragment hash.
Both preserve the output sentinel. Neither emits target LLVM or an object;
Core/CFG/SSA/LLVM, full-source linkage and runtime remain unqualified.
The separate class-storage ledgers return exit1 and record 309,231 nodes;
their source-span inventories are not semantic or stage acceptance.

| Actual operation | O0 wall / peak RSS KiB | O2 wall / peak RSS KiB |
|---|---:|---:|
| Cold C0-built complete test host | 50:49.85 / 2,517,808 | 1:10:43 / 2,518,468 |
| Frozen original source native attempt, refused | 2:10.65 / 303,288 | 0:16.58 / 301,356 |
| Separate class-storage source ledger, exit1 | 0:31.61 / 931,496 | 0:07.02 / 928,372 |
| Exact product reuse, without recompilation | 1.070 s | 1.057 s |

The cold host builds use 3,029.34/4,214.33 user CPU seconds and 1.70 system CPU
seconds each. They overlap and must not be summed as elapsed session time.
The original-only C0 timeout has no completed GNU-time peak-RSS/CPU receipt.
R5's 2,944.88/4,165.4-second cold builds remain historical measurements with
different source bytes; no speedup is claimed. Incremental compiler rebuild
costs, full SSA scaling, the 1,024-block issue and full compiler optimization
are unproved. The resource-accounting repair does not establish those gates.

## Current bounded replays and literal identities

Both current profiles complete all 41 retained recipes, including the 340
inherited source identities, 101 semantic/52 LLVM-valid physical categories,
four exact frozen cohorts and the separate root0/slot6 deferral. The primary
native replay also executes all 71 R5 cases per profile, with independent
C0/Astra LLVM verification, native execution and unsuppressed memory checks.
All 71 source-stage mutation probes, 15 array/6 owner negatives, 32 dynamic
witnesses, Error lifetime and physical consumers are separately recorded.

One primary case, `caller-all`, embeds its own filename, so changing the runtime
directory changes its source bytes. The other 70 primary source identities
match R5 byte-for-byte. `identity.py` independently executes the exact original
caller source **at its original physical path** with each current host and C0,
including stage mutations and clean unsuppressed Valgrind. This retains all 71
original source identities; the new self-filename successor is additional
evidence, not a replacement original. Raw LLVM/Astra ELF/C0 ELF identities are
54/71 for the primary successor set and 55/71 for the exact original-source
pool at each profile. Every differing hash remains explicit; no normalized
comparison is called byte identity. Historical R4/R3 raw identity stays 0/120.

Each current raw 12-job campaign remains **PARTIAL** with two missing-input
failures: `error-order` and `error-physical` initially could not find inherited
fixture records in the new task directory. `fixtures.py` later prepares eight
byte-exact read-only input snapshots without changing any historical original.
`supplement.py` replays only those two jobs in `fix26` leaves at both profiles;
both corrected jobs pass. Detailed independent consumers rebind the corrected
source/IR/ELF/order/memory/LLVM-valid-mutation receipts while preserving the raw
failures. This is distinct from R5's earlier policy/invalid-LLVM failures and
their policyfix3/valid1 supplements. No failed campaign is rewritten as passing.

The first additional product audit compared absolute profile-local object paths
and failed that assertion after validating each product. Its corrected audit
checks 342 common input paths and exactly six named, byte-equal provider objects
in the separate profile directories, plus all 46 exact tool identities. Both
audit attempts remain in the evidence. The production source and products were
unchanged by the audit correction.

Portable order: `build.py` for each profile; `fixtures.py` before `qualify.py`;
`run.py --skip-check` for frozen original-source observations when a separate
C0 check is recorded; `identity.py` for literal historical-source retention;
then `audit.py` after committing task-owned findings. A campaign started before
fixture preparation requires separate `supplement.py` receipts, not alteration
of its failed result. Explicit task build/runtime roots and the authenticated
23.1.4 capsule are required throughout. `evidence.py` packages and verifies
byte-exact content without executing any archived compiler or proof.

The first complete proof encoding contains 51,963 logical files and
3,774,844,489 logical bytes. Its 70,707,996-byte archive exceeds the installed
report-size limit and remains preserved, SHA-256
`e86da4f891269547c9bb74138223aea0dbe4d2fd9749900d7f3096d6ad5dc275`.
The compact encoding uses reversible token/numeric columns for the large raw
observation tables, reusing the independently restored R5 algorithm, and
retains each original blob's exact SHA-256. Binary/UTF8/duplicate/empty and
numeric/whitespace controls round-trip; corrupt columns, duplicate entries,
traversal and orphan payloads are refused. Publication requires complete
reconstruction and comparison against the first payload index, with no dropped
or changed original logical file. This changes proof transport only, with
no semantic inference, root repair or compiler/workflow limit modification.

## Scope-map and constructor verification cycle

The `c13a8ef` observer passes 28 focused source/control cases and the original
190-input conditional Typecore/map probe. The original probe records 53 genuine
instances, 1,245 normalized direct methods and map usage of 121,012 node,
486,786 symbol and 19,603,257 scope entries. Its Typecore observation takes
997.635 seconds. Its separate Flow attempt takes 1,172.458 seconds and refuses
at original `compiler/backend/llvm/recover-owner-emit.astra`, bytes 275–3377.
Both raw outcomes remain preserved. There is no whole-compiler native credit.

The next candidate stores direct-method scopes under their actual ordered
Binder IDs. Genuine generic plans retain their existing dense domains. Map
arrays grow geometrically, with logical coverage and existing node/symbol
ceilings checked independently. The scope consumer reconstructs key coverage,
parent/owner/node/unit/kind/namespace correspondence and copied node/symbol
scope edges. New mutation controls exercise six key corruptions, a missing
mapping and six changed scope fields. These controls await native execution.

Constructor body checks now have pass-local entry points for passes that
independently verify the complete generic map at entry. Standalone verified
entry points retain their complete verification contract. Each local call
still checks the current source fields and body. There is no persisted trust
flag. The candidate also types original payload-free enum construction and
match source facts, with independent source consumers and six mutation
controls. Enum Flow/Core/CFG/SSA/LLVM transport remains unimplemented in this
candidate. The exact C0 oracle uses caller-provided sum storage even for these
payload-free enums. Scalar result transport cannot establish its ABI.

Guarded formatting passes all 18 changed Astra paths, and simultaneous exact-C0
frontend checks pass both development-host entries. These checks establish
frontend acceptance only. An immutable observer build and focused execution
are required before any runtime or performance claim for this candidate.

The completed `2314de0` native gen13 host produces verified O0/O2 objects and
linked exit42 programs for 11 focused positives. These include original Shared
construction, hosted FileHandle, four computed getters, 128/129/186-field
Classes, 262 ordinary members and genuine256. FileHandle descriptor lifetime
and three restored finalizer mutations pass. Genuine257 refuses at exit4,
payload Match at exit3 and the original module at exit4. Their output sentinels
and raw refusals remain preserved. These are predecessor-revision results.

Each observed C0 compilation uses one CPU thread. Independent host builds and
stage-cost jobs have run concurrently on the 32-logical-CPU host. Frozen gen12
cumulative C0 stage observations take 390.386 seconds through CFG, 1,177.210
through SSA and 1,573.188 through native ABI. They ran concurrently and measure
the unchanged development-host C0 path. A perf-event sample was denied by host
permissions, with the refusal retained. The native module probe also refuses
the required enum result channel. No toolchain or installed workflow changed.

## Enum transport and pointer-record candidate

The frozen `c937113` observer passes all 31 focused source/control cases. This
includes six scope-key corruptions, a missing scope mapping, six changed scope
fields and six enum construction/match mutations, with each original state
restored. The two original 190-input probes then run concurrently. Their
whole-source outcomes and costs remain pending at this checkpoint.

The next source candidate carries original payload-free enum values through
structured Flow, Core, range-guarded CFG case chains, SSA and LLVM emission.
Case order, nominal/variant identity, lexical arm cleanup, scrutinee evaluation
and caller channels have independent consumers. The native ABI keeps leading
caller-provided enum result storage before an admitted receiver and explicit
arguments. Checked enum results use that same result storage. Source enum
arguments remain pointer channels with callee-local tag copies. Internal I32
tags use four-byte size/alignment on the authenticated x86-64 target. No
native execution result is established for this candidate yet.

The exact C0 enum method oracle confirms ordinary `void(ptr sum, ptr this)`
and checked `ptr(ptr sum, ptr this, i1)` signatures. The original seven enum
fragments plus the corrected checked-method fixture execute exit42 at O0/O2
with clean unsuppressed Valgrind. The first oracle attempted an unsupported
CLI spelling and the second fixture encountered C0's enum-valued record-field
storage refusal. Both raw attempts remain preserved. The corrected fixture
uses C0-valid function channels. C0's explicit invalid-tag switch successor is
retained as an independently checked fatal range edge in the candidate.

The exact original `RecoverOwnerInstruction` declaration also passes a C0
O0/O2 oracle covering pointer-record returns/arguments, nested records and
Class-owned record arrays. The next candidate admits non-owning void pointer
leaves through existing record shape, layout, carrier and memory consumers.
The original frozen inputs remain read-only and byte-exact. Full original
module generation still requires separate proof.

The gen13 independent audit verifies 197 Git-authenticated archived inputs,
46 tools, 77 artifact references and 24 clean memory streams. Its three raw
refusals remain explicit. The first audit used an incorrect log suffix and is
retained separately from the corrected audit. Guarded formatting and exact-C0
frontend checks pass both new development-host entries. New enum controls
cover three Flow/source, two CFG, four ABI and four LLVM-valid physical
mutations, but their execution is pending the next immutable native host.

ABI source checks now have pass-local entry points within the independently
verified SSA/module boundaries. Standalone entry points retain validation of
the complete checked owner and generic map as before. This removes repeated
whole-owner scans from declaration-level LLVM ABI checks. The candidate has
no measured native speedup yet.

## Measured iteration costs and receiver-root proof reuse

The independent c13/c937 audit binds 109 and 111 consumed Git inputs,
respectively, plus each product's exact tools and command streams. On the
same 190 read-only original inputs, c937 records 953,173 scope-map entries,
53 genuine instances and 1,245 direct methods. Scope occupancy falls 95.1%
from 19,603,257 entries. The conditional Typecore/map probe completes exit0
in 1,047.777 seconds, with peak RSS 273,356 KiB. The earlier probe took
997.635 seconds with peak RSS 437,244 KiB. These revisions also differ in enum
typing and scope verification. The storage reduction is measured, while a
runtime speedup remains unestablished.

The separate c937 Flow probe takes 1,279.233 seconds, peaks at 272,808 KiB
and returns exit2 with diagnostic Flow status3 at node63565. It still refuses
the original pointer-record-returning `recover_llvm_owner_emit` function,
bytes 275–3377. This is the predecessor source revision. Its raw first-stop
receipt remains preserved alongside the ccc1ed1 pointer-record candidate.

One brief read-only GDB sample attaches to the exact scoped Flow worker and
detaches. It shows `generic_calls_verified` invoking recursive Class source
and field checks through `SyntaxArena.node_at`. The Flow timing includes that
sampling interval. The C0 semantic dump and native symbol addresses identify
these frames. The next candidate reuses a receiver type's complete root-depth
proof within the current generic consumer invocation. Its table starts empty
on each invocation. Per-call receiver, source, argument and signature checks
continue for every call. Standalone direct-method predicates retain their full
source check. Three new mutations require a fresh invocation to refuse changed
field flags, declaring owner and source node, followed by restoration.

The Class layout construction pass also reuses its own completed layout rows
before classifying another symbol with the same type. The independent layout
consumer reconstructs the current source separately. Guarded formatting and
both exact-C0 frontend entries pass for the candidate. Execution of its new
controls and matched performance measurements remain pending.

C0 accepts hosted argv-backed `string[]` input channels as `(ptr, i32)` and
reads each string descriptor at stride16/alignment8. Its O0/O2 argv-forwarding
oracles execute exit42 with clean unsuppressed Valgrind. Separate raw capability
attempts preserve C0's refusals for general string-buffer allocation and text
slice slot assignment. The next candidate admits actual read-only, non-owning
string descriptor inputs through existing array source, root, carrier and
physical memory checks. Three original compiler function signatures need these
channels. The focused source library and its C0 driver remain byte-exact in
read-only oracle snapshots. Astra execution of this candidate is pending.

Same-source O2 semantic and native development hosts are building concurrently
under the original C0/LLVM23.1.4 identities. Their purpose is to measure the
cost of executing verification loops with optimized development hosts. Target
O0/O2 generation, native identity, memory and acceptance gates remain separate
receipts. The installed build/workflow scripts remain the ones that authenticate
these snapshots and products.

## Optimized observer costs and constructor source channels

The ccc1ed1 O2 Typecore/Flow observer took 2,014.890 seconds to build. Its
whole-original Typecore observation took 162.812 seconds, the Flow refusal
185.874 seconds and the source-header inventory 172.894 seconds. The inventory
included all 190 original inputs and reported 89 Classes, zero refused Class
declarations, 2,392 functions and 22 refused function headers. Three refusals
need string-array input channels and 19 need constructor source operations.
Body translation and full native compilation remain separate obligations.
The compared earlier O0 measurements use different source revisions.

That observer passed 33 focused source cases. The pointer-record composite
failed Flow with status 1 and 62 nodes. Its raw result is retained. A remaining
producer refusal of pointer-containing records was removed, and constructor
source validation now follows initialized copyable record locals, owned buffer
locals, indexed reads and stores, unqualified Class parameter reads, actual
Class method calls, owned factory results and scalar writes to initialized
owned local Classes. Every receiver and field retains its actual Binder
identity. Hidden constructor receivers remain confined to initialized fields.
Flow, owner, Core, CFG, SSA and physical consumers still verify their respective
obligations. Focused Astra execution of these constructor changes is pending.

The new constructor-channel fixture returned 42 under original C0 at O0 and
O2 with clean unsuppressed Valgrind results. The first oracle attempt's direct
owned return was refused by C0 and is retained. The corrected fixture uses an
owned local followed by an explicit move. Its read-only oracle snapshots bind
the exact corrected source. Added restored mutation controls exercise
initialization, local ownership and read-only field authority. The existing
Shared parameter control now also checks valid unqualified parameter reads
and uses an invalid flag value for its refusal mutation.

The ccc1ed1 O0 native host built in 3,574.913 seconds. It generated and linked
the original payload-free enum and enum ABI cases at both target profiles,
each returning 42 with clean unsuppressed Valgrind results. Its pointer-record
composite refusal remains raw. The corresponding O2 host build reached the
recipe's 3,600-second timeout and failed after 3,602.217 seconds. An explicit
compile-plan recipe permits a larger recorded budget for authenticated Git
snapshots while retaining original build and timeout receipts. It validates
the exact C0, source population, input bytes, tools and environment before
execution and repeats input identity checks before recording a product.

The old c13 source inventory was explicitly stopped with exit 143 after
preserving partial output. It has no completed inventory verdict. The finished
O2 inventory supplies the current source-header diagnostic counts above.

## Record-local mutation candidate and iteration checks

The next candidate retains mutable copyable record locals in actual lexical
stack slots. Record field writes carry the source local and exact nested field
path through Flow, Core, CFG and SSA. LLVM updates only the selected flattened
subtree after loading the current record. The physical consumer independently
reconstructs source leaf offsets and checks every load, extraction, insertion
and store in order. Mutable projections reload the same actual slot, and whole
record reassignment uses the existing mutable-local machinery. SSA checks that
the original local declaration dominates reads and writes. By-value record
parameters retain C0's read-only contract. Record-array field mutation remains
an open body-translation obligation.

The focused nested-record and whole-record reassignment fixture passes original
C0 O0/O2 execution and clean unsuppressed Valgrind. Astra source and native
execution of this candidate are pending. Restored controls cover source roots,
read-only parameter authority, mutation-index coverage, CFG correspondence and
four LLVM-valid physical mutations. These controls require actual execution.

The 314c965 constructor observer build failed C0 Core verification in a newly
added test control that projected a temporary record directly into an index.
The control now binds the source node to a local before reading its index.
The failed build remains retained. Both development entries then passed C0
semantic and Core preflight checks. A separate frontend refusal of a borrowed
CheckedIndex local in the record emitter was corrected by passing that actual
owner as a temporary argument. Its raw failed check is also retained. Later
Core checks precede expensive native rebuilds.

The 3486f4d O2 source observer passes 35 of 36 focused checks, with the raw
pointer-record composite failure retained. Its complete-original inventory
has 19 constructor header refusals after the three string-array headers were
cleared. Whole-original Typecore took 158.922 seconds, Flow 168.476 seconds and
the inventory 169.463 seconds. The separate gen14 native audit authenticates
14 positive programs at both target profiles, 28 linked returning products,
13 restored enum transport controls and the literal pointer-record, generic
257, copied payload-Match and complete-original refusals. Complete original
native profiles remain zero of two.

Three read-only stack samples of the 3486f4d O2 Typecore observer found repeated
Class storage traversal and linear Error-root searches during method selection.
The next producer candidate scans the current BindingIndex symbol discriminators
directly, copying complete declaration records only for Class symbols. Every
query still checks the current original symbol range and duplicate annotations.
The source query retains no cached root. Restored controls compare it with the
previous full-record reference scan, including changed kinds, absent and duplicate
annotations and invalid range bounds. Runtime benefit awaits measurement.

## Record-array field mutation candidate

Record-array field writes now retain the actual container, subscript and nested
source field path. The existing checked array target runs before the RHS. After
successful RHS evaluation, the emitter reloads the current element through its
verified record-memory helper, replaces the selected flattened leaves and stores
the complete updated element. Sibling-field changes made by the RHS are retained.
An error successor skips the update. Existing root, projection preservation,
mutability, lifetime, bounds and SSA dominance checks cover the captured address.
The physical consumer reconstructs leaf positions independently and checks both
memory-helper calls and every intervening extraction and insertion.

The focused C0 witness covers an owned local array, a borrowed array parameter,
a private Class-owned buffer, nested scalar and subrecord updates, RHS mutation
of another field, checked success and checked error, and final cleanup. Exact
original C0 O0/O2 products return 42 with clean unsuppressed Valgrind. The earlier
unchecked-only witness remains in its own read-only oracle. C0 separately refuses
the negative where the RHS consumes the backing owner. Astra execution and ten
restored source, CFG and LLVM-valid physical controls remain pending.

The LLVM frame consumer also verifies that mutable and owning lexical frames
occur in source storage order as distinct consecutive entry allocations. This
uses a linear instruction-order check. A restored metadata control aliases two
same-type record frame entries and requires refusal. Its control status remains
separate from the four physical record-local mutation controls.

The first record-array native preflight encountered an already existing build
leaf and preserved it. The next attempt uses a new task-specific leaf. Its
formatter and semantic-only observer check had completed successfully.
The fresh native semantic check then required the array emitter's source-shape
validation Error to propagate through its declared checked contract. After that
correction, both development entries passed semantic and Core preflights.

## Constructor context and Flow integration correction

The cd5cfee O2 observer completed 40 focused checks. It passed 37, including
pointer-record Flow and fresh Error-root reference controls. Constructor-channel
controls, constructor-channel Flow and record-local Flow failed. Their raw
receipts remain retained. The complete original source inventory reduced the
constructor header refusals from 19 to five. Whole-original Typecore took
143.892 seconds, Flow 150.092 seconds and the inventory 152.389 seconds. These
single observations use a changed candidate revision and do not isolate a
runtime speedup.

The integration correction permits the verified owned-result function flag in
constructor factory calls and includes record-write tokens and local symbols
in the Flow node checks. Constructor reads now follow independently verified
scalar properties and actual getter argument edges. Caught checked calls carry
the actual nominated Error catch bound through the constructor source walk.
The public source predicates enter with an empty handler and continue to refuse
unhandled checked calls. The expanded C0 constructor witness exercises scalar
and computed getters, owned factory results and both caught-call outcomes at
O0/O2 with clean unsuppressed Valgrind. Two additional restored controls require
refusal for an invalid catch binding and an unhandled checked call.

The completed 314c965 C0 development-host builds took 3,651.249 seconds at O0
and 4,381.297 seconds at O2 under explicit 7,200-second budgets. Both hosts
retained 14 positive native programs in their follow-ups. Both refused the
constructor-channel witness at source admission and the pointer-record witness
after valid Flow and SSA, while constructing LLVM record helpers. Whole-original
native attempts were deferred after those focused failures. The raw results
and the earlier 3,600-second timeout remain separate receipts.

The record helper emitter's leaf selector and its independent memory-leaf
consumer still excluded pointers. The correction admits the source-qualified
address-space-zero pointer leaf in both paths, preserving the existing depth,
field and leaf ceilings. Both development entries pass C0 semantic and Core
preflights with these corrections. Astra execution is pending.

## Complete original headers and nested record initializers

The 45b2bed O2 source observer builds in 2,110.555 seconds and passes all
42 focused source/control cases. The complete 190-input original Typecore
check takes 138.378 seconds with 269,588 KiB peak RSS. The source inventory
takes 147.025 seconds and admits all 89 Classes and 2,392 function headers.
Whole-original Flow takes 151.395 seconds and stops at status 2 with
38,352 nodes, preserving that raw failure.

Read-only failure breakpoints identify original `compiler/cfg/lower.astra`
function `cfg_payload`, bytes 144–559. Its initializer at bytes 224–496 uses
inline nested record fields. The builder passes a zero expression child to
the edge table because these fields retain their inner record through the
separate initializer child. The recorded stop has 14 nodes and two edges in
this function, an 8,192 per-function limit and status zero immediately before
the invalid-edge failure. The function and fragment match the original Git
bytes. An initial host-library identity refusal and two incomplete debugger
setup attempts remain separate diagnostic receipts.

The candidate follows the actual nested initializer child in construction,
constructor reads and the independent Source/Flow consumer. Source validation
requires exactly one expression/initializer child, the actual declared field
identity and type, and a copyable nested record type. Five restored source
controls cover missing/dual children, child/field type corruption and a changed
field name. Their Astra execution remains pending. The new C0 witness uses
inline nested records in a constructor and ordinary function, copies a returned
record into an owned array, and exits42 at O0/O2 with clean unsuppressed
Valgrind. Complete original Flow and native qualification remain outstanding.

The source observer also gains `--construction-inventory`. It retains the
complete checked source and genuine function/signature inventory, then creates
a fresh construction table for every original function. Each body passes
through the existing builder, independent source/tree consumer, loop consumer
and node/edge coverage checks. Every refused function keeps its status and
original span. This batches diagnosis across successive source blockers. The
complete-module field, owner and IR consumers remain acceptance requirements.
The original whole-module failure is retained alongside this diagnostic mode.
Guarded formatting and C0 semantic/Core checks pass the candidate. The batch
driver's first preflight caught its missing checked Error declaration. The
corrected driver passes a fresh preflight. Exact source/tool checks reuse the
already passing native entry checks after the observer-only edit.

The 45b2bed O2 native development host completes its C0 compilation in
4,410.885 seconds. Its 18 focused source programs produce actual target O0/O2
objects and 36 linked exit42 ELFs, with 38 clean unsuppressed memory streams
including FileHandle descriptor checks. Constructor channels, pointer records,
record-local mutation and record-array mutation all pass. Restored controls
cover 13 enum transport, nine record-local, one frame-metadata, ten record-array
and three finalizer alternatives. The backing-invalidation source retains its
actual Flow status 1 refusal and unchanged output sentinel.

The independent native audit authenticates both target profiles, compile
identity, every consumed Git input and the complete source attempts. The
190-input original module stops at Flow status 2 after 38,352 nodes. The
199-input current module stops at Flow status 2 after 43,501 nodes. Both retain
their output sentinels. The genuine 257-instance case and copied-payload Match
source keep their separate refusals. Full original compiler native
qualification remains 0/2 profiles.

## Bounded parallel regression execution

The milestone regression wrapper accepts `--jobs 1` through `--jobs 8` and
defaults to its existing serial execution. Each job retains its own process
group, timeout, output streams and GNU-time receipt. Source-stage mutations
wait for their actual original/native fixture producer. The strict drift ledger
waits for the complete retained recipe campaign. The main thread writes results
as jobs finish, retaining the original job order in each receipt and preserving
failed-command ordering.

Synthetic scheduling controls cover one-worker compatibility, four-worker
overlap, an eight-worker run, both fixture dependencies, injected raw failures
and injected process-group timeouts. Complete synthetic streams and scheduler
events are retained. They confer zero native qualification credit. Actual
parallel native campaign timing remains pending. The active development batch
uses one O2 native host for intermediate target O0/O2 checks, alongside the
independently built O2 source observer. Final qualification still requires
matching O0/O2 compiler products from the completed source revision.

The completed cd5cfee native pair took 3,728.959 and 4,408.223 seconds in its
recorded C0 compilation commands. Each host retained 14 positive native
programs at both target profiles, with 30 clean unsuppressed memory streams.
The independent audit authenticates Git inputs, tools, compile plans and
56 total Astra fixture ELFs. Both hosts retain the raw record-local Flow
refusal, constructor source refusal and pointer-record LLVM-helper refusal,
plus the genuine257 and copied-payload Match refusals. Their whole-original
attempts remain deferred after focused failures. The subsequent 45b2bed results
above retain their separate source and product identities.

## Complete original construction inventory and shift preflight

The ef59a11 O2 source observer compiles in 2,177.588 seconds. Its focused
batch records 44 passing cases and one raw mutation-driver failure. The new
nested-record witness passes Source/Flow with 96 nodes. The mutation driver
selects an untyped original constructor initializer and exits8. A read-only
breakpoint receipt binds that selection. The corrected driver requires a typed
initializer, and its compiled execution remains pending.

Separate full-original diagnostics retain all 190 byte-exact source inputs.
Typecore and all 89 Class / 2,392 runtime function headers pass. The diagnostic
inventory examines every required function instance. Independent source-tree,
loop and coverage checks pass for 2,290 bodies, or 95.7 percent, and record
102 refusals with original spans and fragment hashes. The independent audit
`source-observers-independent-audit7.json` binds the product, original inputs,
raw failed mutation case and all refusal fragments. Whole-module Flow reaches
284,462 nodes and retains its exit2, internal status3 refusal. A read-only
storage breakpoint identifies the first inventory stop after 3,492 slots at
original `compiler/backend/llvm/check.astra` line149, `var op = text.text;`.
Borrowed-text lifetime admission and the remaining source refusals require
implementation and qualification. Full original native qualification remains
0/2 profiles.

Integer shifts now have guarded LLVM helpers for all ten operand kinds, ten
count kinds and both directions. The guard rejects negative and out-of-range
counts before truncation or extension. Signed right shifts use arithmetic
shifts, unsigned right shifts use logical shifts. The independent physical
consumer reconstructs signatures, blocks, guard edges, count normalization,
operations, flags and closed instruction inventories. Module validation retains
every required helper and verifies each actual call.

`shift-runtime.py` builds the complete production helper definitions and pure
consumer definitions under original C0 in the verified LLVM23.1.4 capsule.
O0/O2 C0 producers each test O0/O2 target ELFs. Each of the four combinations
compares 180,960 valid shifts against C0 reference operations and records a
clean unsuppressed Valgrind stream. Every count kind and direction also has
matched negative/out-of-range trap receipts. Twenty independently LLVM-valid
physical mutation categories are rejected, with fresh positive checks before
each mutation. The immutable-witness rerun takes 3.08 / 3.33 seconds for helper
emitter compilation. `shift-runtime-independent-audit1.json` authenticates all
382 commands, sources, IR, native identities and memory streams. The recipe
records zero Astra-native credit. Whole-pipeline shift execution remains
pending. Guarded formatting and native-driver semantic/Core preflights pass
after correcting a temporary borrowed-child selection caught by the first
native preflight. Earlier failed formatter and preflight receipts are retained.

## Borrowed text and lexical receiver-spelling candidates

The text-local candidate admits immutable descriptor copies from module
literals, caller text, other immutable text locals, literal-returning calls and
direct readonly text fields/accessors of actual Class receivers. Its separate
consumer reconstructs provenance, lexical scope ancestry and every actual
receiver move or rebinding. A moved receiver currently leaves the complete
function unsupported, including moves after the final view use. Nested receiver
projections and mutable text locals await further lifetime proofs. Existing
literal-only result validation continues to guard string-returning calls.

The new source witness covers caller, literal-call, owned receiver, borrowed
receiver, copied descriptors and a nested lexical scope. Six restored mutation
controls target readonly/type facts, receiver moves, descriptor assignment,
scope ancestry and receiver ownership. Guarded formatting and both compiler
drivers' C0 semantic/Core preflights pass. Original C0 O0/O2 executions and
unsuppressed Valgrind pass. Astra Source/Flow and target native execution of
the candidate remain pending.

A separate exact-original `generic_window_bounds` witness reproduces a raw
Flow status1 refusal with 61 nodes. Read-only entry/return breakpoints bind
the original C0-produced observer and identify `base` name expressions with
pending reason13 and type0. The binder had overridden the resolved lexical
parameter with implicit-receiver reason2. The correction retains an actual
resolved declaration through that spelling-sensitive branch. Parameter, local,
record-field and Class-method witnesses pass C0 O0/O2 with clean unsuppressed
Valgrind, alongside the exact original numeric bounds function. Both compiler
drivers' semantic/Core preflights pass. Compiled Astra observer execution is
pending. The same focused oracle batch confirms the mixed-width shift and
boolean bitwise witness at C0 O0/O2.

## Verified text/binding batch and subsequent construction work

The 7c605eb O2 observer completes its actual C0 compilation in 2,200.968
seconds with 1,689,112 KiB maximum RSS. Its ELF SHA-256 is
`c68b6358658e53632a4fe9bc66af2896555c924fe2d476a6487d8f20ad0af428`.
All 49 focused Source/Flow cases pass, including the five nested-initializer
controls, six text-view controls, mixed-width shifts and lexical `base`
bindings. The independent audit authenticates 114 consumed Git inputs,
the tool identities and all original input bytes. All 89 Class and 2,392
runtime function headers pass. Isolated body construction/source checks pass
for 2,318 of 2,392 functions, or 96.9 percent, with 74 exact refusals retained.
Whole-original Flow retains exit2, internal status3 at original
`recover-utf8.astra` line52, `text.text`, after 284,462 nodes. Complete original
native qualification remains 0/2.

Further read-only diagnostics identify three concrete requirements. The exact
original floating checker stops at `a as f32`. The original path comparator
passes its recursive source/tree check but retains two unseen `first.text` /
`last.text` nodes constructed twice for `.text.byte_length`. Counting every
required original parameter/local gives 20,656 slots, at most 313 in one
function, compared with the former 8,192 aggregate table.

The next candidate builds text-length projections once, admits integer-to-float
and f32/f64 width changes, and sizes module storage from the actual bound symbol
inventory. Producer and independent consumer retain 8,192 slots per function
and the 8,000,000 aggregate bound. A 601-function C0 witness requires 9,600
parameter slots, sixteen per function. Its O0/O2 oracles exit42 with clean
unsuppressed Valgrind. Six source/storage mutation controls await observer
execution. The first control-driver preflight catches a projected scalar write
requiring a complete receiver loan. The corrected helper passes fresh checks.

Caller/module-backed text descriptors can also be reassigned. Every replacement
is independently checked for caller/module provenance. Class-backed local views
retain their immutable receiver/scope proof. Direct byte-length reads of mutable
text reload the current descriptor, with an independent load/extract inventory
check. The expanded text witness and floating-cast source witness pass original
C0 O0/O2 with clean unsuppressed memory. Their Astra pipeline runs remain pending.

The floating helper preflight compares 22 conversions plus two identity
transports against original C0 bitwise, 120,384 observations per producer/target
combination at O0/O2. It also checks 192 constant cases and eight independently
LLVM-valid physical mutations, with four clean unsuppressed memory streams.
Early harness attempts retain their invalid same-type C0 cast, missing metadata
declarations and out-of-width constant refusals. The corrected constant producer
masks each declared integer width. The existing unchanged array/cast recipe
passes its 24 LLVM-valid categories after restoration of its four-argument
verifier entry point. Record indexing uses the explicit shape verifier.
Historical directories retain read-only mounts, and a recorded output-root
adapter directs this replay into the milestone26 directories.

`source-observers-independent-audit8.json` and
`completion-helper-independent-audit1.json` bind these separate outcomes.
Both compiler drivers pass semantic/Core preflights. Complete original
Core/CFG/SSA/LLVM, representative linkage and owner-root qualification remain
outstanding.

## Continued source admission and indexed Class borrows

The observer built from `598414d` passes all 54 focused cases, including the
expanded mutable-text witness, floating casts and six storage correspondence
controls. Its frozen 190-file original population retains 89 Class headers and
2,392 runtime function headers. Isolated construction/source checks pass 2,345
bodies, or 98.0 percent, with 47 refusals. Whole-original Flow retains exit2,
internal status1 after 284,425 nodes. Complete original native qualification
remains 0/2. These measurements supersede the earlier isolated-body count while
preserving every earlier failed receipt.

Direct borrowed inspections of owning Class slots account for many remaining
original bodies. A focused witness covers nested backing fields, dynamic indices
and two simultaneous inspection arguments. Original C0 O0/O2 executions exit42
with clean unsuppressed Valgrind. The preceding observer refuses its Flow.
Early witness attempts retain C0 refusals for indexed field extraction and a
heap-field construction form, plus a runtime trap from omitted reserve capacity.

The candidate admits an indexed Class value only as an exact-Class borrowed
inspection argument. Source checks reconstruct the actual backing receiver,
captured projections and other-argument preservation. Core records its borrowed
role and real receiver storage slot. SSA follows the paths to its single call
consumer and rejects retirement, captured-field replacement or intervening slot
mutation. LLVM uses the existing checked pointer-index helper, with independent
AS0 load, operand, bounds and closed-inventory checks. Source, Core, liveness
and LLVM mutation controls are authored. Their updated Astra executions remain
pending. The first Source-only test preflight reports an unavailable Core helper;
the corrected test performs its own bounded parenthesis traversal. Raw receipts
are retained.

## Guarded float-to-integer conversions and enum reassignment

`source-observers-independent-audit9.json` independently binds the `598414d`
observer, 114 consumed Git inputs, 46 tool identities, all 190 original target
files and 202 current target files. Its original and current Typecore/header
runs pass. Both whole Flow runs retain exit2. The 54 focused passes and exact
2,345/2,392 body inventory remain source-stage observations.

The original numeric checker also requires floating-to-integer casts. The
candidate uses ordered range guards before conversion, including the signed
64-bit minimum, fractional negative unsigned inputs, NaNs and infinities.
The independent LLVM consumer reconstructs fixed mathematical bounds and checks
the complete helper bodies, guard edges, operations, operands, attributes,
metadata and module inventory. Twenty physical helpers cover both floating
source types and all ten integer destinations. The first native preflight
catches an undeclared checked Error from source-derived helper naming. The
caller now propagates that existing bound through its checked verifier caller.
Both complete driver semantic/Core preflights then pass.

`float-integer-runtime-proof1/result.json` records 83,644 valid bit comparisons
for each of four C0-producer/target O0/O2 combinations, 320 matched fatal pairs,
sixteen independently LLVM-valid mutation categories and four clean unsuppressed
memory runs. All 694 command receipts remain available. Complete helper-source
snapshots and byte-exact helper views are retained. These tests contribute zero
Astra-pipeline or whole-compiler qualification credit.

The remaining original `flow_constant_admitted` body also reassigns a
payload-free enum local. Its nominal copy channel now requires the existing
independent empty-payload enum proof. The focused enum-reassignment and twenty
floating-to-integer source functions pass original C0 O0/O2, exit42 and clean
unsuppressed Valgrind. The preceding Astra observer refuses both witnesses.
Updated Source/Core/CFG/SSA/LLVM executions remain pending.

The indexed-Class development builds use immutable `60838e1` inputs. Their
source observer and complete O0 native host run concurrently. O0 was selected
for the development host to reduce rebuild cost. Final matching O0/O2 products
and qualification still require the completed implementation revision.

## Preserved obligations

Historical R4 and initial R5 remain PARTIAL. R5 engineering G0–G11 remains its
reported PASS, with the new host G12 verdict separately attributed. Its raw
12-job campaigns still have `error-physical` and `retained-41-recipes` failures;
the policyfix3/valid1 supplements do not rewrite them. R4/R3 raw LLVM identity
remains 0/120. Historical four-cohort, 56/12/12, 17/19, mutation, negative and
dynamic receipts remain tied to their original products. The current replays
above are separate measurements and do not relabel historical qualifications.

`CheckedIndex.add_signature` graph55/symbol2053/predicate26 remains independently
DEFERRED: `this.signatures` root0 versus `grown` slot6. No owning receiver root
was invented, and no verifier or original source was excluded to make progress.
Original C0, public C ABI, approved E25-A-v1 proposal
`d77c02f3144ab5dc3da41eb310b29cd02629b49876042934ea5071a1549ac66e`,
module-owned LLVM cache lifetime, donor and all safety ceilings are preserved.
No push, release, history rewrite or Stage1 work is authorized or performed.
