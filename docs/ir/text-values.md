# Text values and stage ownership

`TextBytes` is a stage-neutral immutable leaf: a copied byte array and explicit
int64 compiler count, validated as 0..INT32_MAX with exact array correspondence
and UTF-8 shortest-form/scalar checks. It retains no source, syntax, semantic
universe, name, owner or preceding program. Embedded zeros survive lossless hex
dumps, constant aliases and LLVM data emission. Payloads never enter quark tables.

| Stage | Text authority |
| --- | --- |
| Syntax | TextLiteralExpressionSyntax token, decoded payload and byte span; bounded postfix TextMemberExpressionSyntax |
| Checked | Canonical StringType; CheckedTextExpression/CheckedTextLengthExpression; exact constant text values; native boundary contracts |
| Core | CoreTextValue/CoreTextLengthValue; program-owned literal membership; no constant symbols/evaluator |
| CFG | CfgTextValue/CfgTextLengthValue plus existing ordered evaluation and local/temporary definitions |
| SSA | SsaTextConstant/SsaTextLengthInstruction; StringType instruction results, block parameters, calls and returns |
| NABI | Independent NativeTextType with exact PTR/I32 fields and BORROWED_NOESCAPE or STATIC_TEXT |
| LLVM | Private byte constants, backend-only {ptr,i32} values and one optional bounded equality helper |

One logical StringType value is one indivisible text group. It has no operation
exposing its base or constructing a view from unrelated scalar components. Local
SSA promotion, branch/loop block parameters and call/return values preserve this
group. Existing specialized paired-view machinery handles physical transport;
there is no universal aggregate Astra SSA expression or text-copy alloca.

Each executable program owns its literal membership list. Core/CFG/SSA verifiers
independently reject invalid counts, invalid UTF-8, nonmember leaves, inconsistent
StringType identities and invalid boundary contracts. Ordinary operand/type,
function membership, dominance, call, edge and return verifiers remain active.
Standalone text witnesses forge malformed state and expired callees without
constructing a frontend. NativeTextType has no semantic or SSA dependencies.

Static-result proof tracks backing origins, not descriptor lifetimes. Semantic
and Core passes capture a fresh origin version at each write; structured joins
and loop headers produce finite equations, with break/continue edges. CFG derives
entry versions and predecessor equations independently. SSA derives equations
from exact block arguments and definitions. A worklist rejects unknown/borrowed
roots and requires every terminal origin cycle to reach static grounding. These
construction/verification graphs die immediately; they are not runtime metadata.

Every native StringType result is a STATIC_TEXT obligation. All definitions,
including recursive definitions, are checked before publishing the program.
Calls refer to that obligation, not current call-site provenance. A recursive
function with no terminating path returns no value; every actual return-producing
path must meet the static contract. Unverified definitions cannot publish a
borrowed result through optimistic inference.

LLVM sees already-decoded bytes, final type identity and independently checked
plans. First emitted use in canonical function/block traversal determines
`astra.text.N`; callable/type ordinals are untouched. The pool key includes count
and full byte content, with ordinary hash collision equality. Empty text is
{null,0}; other data is private read-only exact-length storage without a sentinel.
Unused constants do not force emission. Address identity is never an equality
rule; LLVM globals retain ordinary address significance.

Equality evaluates already-sequenced SSA operands, then calls one internal
helper. Different lengths return false, equal empty views true without loads,
and the remaining loop reads exactly [0,count). No strlen/strcmp/memcmp import,
UTF-8 rescan, allocation or runtime registry is needed. The helper has local
`no-builtins` and `noinline` attributes under LLVM 22; numerical/ownership
optimization policy is unchanged. LLVM may infer valid helper memory effects,
but the compiler does not mark entire callers readnone/readonly, nor add noalias
or nonnull to text. The helper uses its own LLVM blocks, so text equality does
not split the caller's physical continuation; numeric guard splits still use
the existing final-predecessor bookkeeping for phis.

The lifetime tests destroy per-file syntax, constants, checked functions,
semantic universes, Core, CFG and SSA before verifying the next artifacts.
NABI remains verifiable after SSA destruction. LLVM module verification after
all predecessors and source files die demonstrates owned backend data. Ordinary
span owners keep sources only as long as diagnostics need them.

TEXT-IO-1 preserves this representation for ordinary foreign call arguments.
Normalized text metadata belongs to the exact C callee. Core/CFG/SSA verify the
explicit mode and borrowed parameter contract without splitting the StringType
value. The independent CABI sidecar owns the foreign group plan; only LLVM
boundary lowering extracts its captured data/count components. No POSIX symbol,
provider dispatch or C-string conversion enters Core.
