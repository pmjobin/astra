# Native struct value boundary IR

[Record elements](struct-elements.md) can supply bounded struct arguments/results and receive exact call results. Fixed-array producer entries require complete result-leaf consumption. SSA retains scalar/vector leaves, with no new aggregate value or phi.

Struct boundary contracts preserve exact nominal type and COPY_VALUE semantics.
They do not create a universal StructValue, an aggregate load/store Value, or an
aggregate SSA phi. The bounded call/result grouping is separate from ordinary
scalar/vector expression Values and from identity-bearing ObjectStorage results.

| Stage | Contract/producer representation | Transport |
| --- | --- | --- |
| Checked | StructValueContract; CheckedStructSnapshot / CheckedStructCallResult | Exact producer and provenance |
| Core | Independent StructValueContract; CoreStructSnapshot / CoreStructCallResult | Exact stage-owned Places/callee/ordered arguments |
| CFG | StructValueShape; StructBoundaryGroup; CfgStructCallResults | Ordinary concrete parameter, snapshot and result leaf Values |
| SSA | Same stage-neutral shape/group; SsaStructCallResults | N ordinary SsaInstructionResults owned by one call identity |
| NABI | NativeStructValuePlan and NativeStructParameterPlan | Copied declaration identity and physical leaf channels |
| LLVM | Concrete function signature and carrier grouping | Flat parameters; leaf or backend aggregate result |

CheckedStructProducer is a CheckedNode, not a CheckedExpression.
CoreStructProducer is a CoreNode, not a CoreValue. Each permits only a Place
snapshot or an ordinary exact native call result. The CheckedStructArgument and
CoreStructArgument expression adapters are accepted only while verifying an exact
struct parameter's argument. They are rejected by general Value verification.
Result-store statements distinguish fresh local initialization from assignment;
struct-return statements retain a complete exact producer. Discarded struct-call
results reject. No general aggregate operation inherits this bounded permission.

Core parameters/results retain independent StructValueContracts. The parameter's
CoreLocalPlace points to its exact incoming CoreParameter. CoreAcquireStructParameter
initializes every leaf before body statements, after any ordinary owned-parameter
acquisition prefix. Parameter storage is read-only, including recursive writes
and address-taking. A local copy can be mutable. CoreVerifier checks explicit
contracts, exact nominal compatibility, copyability, complete initialization,
producer consumer uniqueness, legal destinations, and native callee identity.

CopyabilityAuthority.of(type, fields) remains the sole eligibility rule. Each
stage resolves fields from its own graph. StructLeafOrder is the single recursive
declaration-order walk factored from STRUCT-COPY-1. CoreStructLeaves maps those
ordinal paths back to exact Core fields; both whole-copy and ABI lowering use it.
Each vector is one leaf. Padding is never enumerated. Concrete generic applications
materialize to ordinary StructTypes before CFG. Parameterized aggregates fail
closed; there is no generic aggregate boundary contract at NABI.

## CFG sequencing and SSA promotion

One source parameter becomes N ordinary CfgParameters plus nominal grouping.
Entry Initialize operations map incoming leaf values to parameter-local field
Places. These are local definitions, never aliases of caller storage. Field reads
use existing leaf Loads. Parameter/argument group offsets index the stage's
parameter array; existing slice groups retain their own two-channel expansion.
Receivers and object result-storage contracts remain separate.

At each struct argument position, Core→CFG captures and validates its source Place,
then emits CfgEvaluateInstruction(CfgLoadValue(leaf), snapshot) in shared leaf
order. Only then can later argument effects run. A struct-returning call creates
one CfgStructCallResults containing N ordinary CfgCallResultValues. It has no
aggregate CfgValue or scalar call result. CfgStructResultConsume identifies one
complete initialization, assignment, argument or return consumer. Destination
writes follow complete production; forwarding has no intermediate storage.
CfgStructReturn carries the exact shape and ordered leaf return list, captured
before existing cleanup instructions.

SSA promotion maps those leaves directly to local field definitions. The same
call owns N ordinary SsaInstructionResults and one SsaStructCallResults grouping,
which is not an SsaValue. The resultless consumption marker survives promotion
so a scalarized initialization still has a verified complete bounded consumer.
Definitions cannot be used before that consumer dominates them. Argument/return
forwarding must use the exact full ordered set. Storage consumption releases the
leaves into ordinary field definitions; memory-backed destinations emit ordinary
recursive stores. Returns carry ordered SsaValues. Branches merge corresponding
leaves using ordinary scalar/vector block parameters; no aggregate phi exists.

## Stage lifetime and backend firewall

Checked graphs and symbols may die before Core verification. Core fields and
functions may die before CFG verification, and CFG may die before SSA verification.
SSA may die after completed NABI/CABI planning. LLVMArtifact owns no prior graph
or SourceFile after lowering. Tests assert those lifetimes with weak references.
No stage recovers meaning from source text, debug names, LLVM layout or padding.

NABI construction validates exact SSA-to-plan declaration association, count,
order, leaf channels, source parameter groups and carrier choice. Standalone
NABI model/verifier/dump sources contain no semantic/SSA/LLVM graph dependency.
The physical plan's ordinal/name is copied identity/provenance, not a semantic
type constructor or structural compatibility rule.

LLVM receives concrete leaf channels and a concrete single/multiple result plan.
For multiple leaves it builds/extracts an LLVM literal struct solely at call/return
boundaries. Carriers are not stored merely to unpack them. There is no mandatory
aggregate alloca, input pointer, hidden result pointer, sret, byval or memory
intrinsic. Existing selective addressability still supports explicit memory.
Numerical conversions, FMA/fast-math policy, C ABI and ownership are unchanged.
See [native aggregate ABI](../abi/native-aggregates-v7.md) and
[ADR 0062](../decisions/0062-native-struct-values.md).
