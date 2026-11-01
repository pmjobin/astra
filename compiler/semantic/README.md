# Presemantic binding component

`binding_index(move program, 0)` consumes and retains the typed `SyntaxProgram`.
This separate Astra component does not replace production Vala C0. No type
checker, Stage 1, IR, backend or release qualification is implied.

`SymbolId`, `ScopeId` and node/token IDs are distinct, local to their owner.
Checked accessors reject zero/out-of-range IDs. Symbol rows retain original
node, token, source/half-open byte span, source order, short/canonical names,
kind, domain, scope, owner and visibility. Imports reference existing namespace
identities. A spelling is a lookup key; it is never a declaration identity.
Externally comparable identity is `normalized-path#start:end`. Equal bytes in
separate source objects/files do not merge declarations.

Scopes have only nonowning ordinal parent/owner edges. The index owns dense
geometrically grown symbol/scope/reference/work arrays and one text pool. The
program owns sources and the AST. No symbol owns a node or another symbol.
Construction failure and destruction release arrays and their retained program
without recursively traversing scope edges. Scheduling uses an explicit stack;
`generate-walk.py` derives only typed child scheduling from the existing schema.
Binding decisions are maintained in `index.astra`, independently of SyntaxDump.
Duplicate metadata views (members versus fields/methods, cached applications,
property factory mirrors, inherited vector operands) are visited once.

The category/deferral ledger is `port.json`; raw current results remain external.

The API enumerates symbols/scopes/references through counts and checked copied
records; `resolve` takes an explicit scope, node, token, spelling and domain;
`scope_for_node` locates syntax context; `reference_at` queries source offsets.
Each symbol's `first_reference` and each edge's `next_reference` form a reverse
reference list. The query executable exercises these APIs after lexer/parser
handles have been retired. The retained program keeps all spans valid.

Lookup uses an open-addressed table keyed by domain plus canonical spelling for
globals and domain plus scope plus spelling for lexical names. Types and values
are disjoint. Same-namespace lookup precedes ordered imports, inaccessible
imports are skipped, explicit qualification checks internal visibility, and
fallback uses the global namespace. Import ambiguity records both candidates.
Free names are collected before uses; local initializers precede local insertion.
C0 `ValueScope.lookup` forbids hiding an active local/parameter; sibling blocks
can reuse a name. The source of truth is `bootstrap/semantic/analyzer.vala`
(`collect_modules`, `resolve_name`, `ValueScope`, declaration/body checking).

The development observation is `astra-bindings/1`, whitespace-separated rows.
Text fields are lowercase UTF-8 hex, offsets are decimal half-open byte ranges.
It is an internal observation, with no serialized/public ABI promise:

- `D ordinal path start end name canonical kind domain scope owner node`.
- `S ordinal parent owner kind node`.
- `R ordinal path start end state target alternative scope domain reason node`.
- `C syntax-kind-code visited-count` instruments typed scheduling coverage.
- `ERROR path start end message` replaces declaration/reference output on failure.

Symbol kinds: function 1, constant 2, struct 3, class/foreign type 4, enum 5,
field 6, formal 7, local 8, type parameter 9, namespace 10, method 11,
lifecycle 12, variant 13, property 14, loop/catch/pattern binding 15,
async runtime 16, payload 17, accessor 18. Domains: type 1, value 2, namespace 3, member 4.
Reference states: bound 1, unknown 2, ambiguous 3, inaccessible 4, deferred 5,
builtin 6. Builtins have no source declaration. Deferrals never create a target.

`astra-bind-O0 --index FILE...` observes a multi-source index.
`--definition PATH OFFSET FILE...` reports the containing reference and target.
`--references PATH DECLARATION_START FILE...` follows the actual reverse list.
`--partial COUNT FILE...` is a deterministic construction-failure control.
Source paths are normalized by SourceSet, preserving case and `..`; sources are
sorted before parsing. Output order follows deterministic source/typed traversal,
never hash iteration. Reverse lists have reverse insertion order.

Only genuinely receiver/type-directed selections are deferred. Reasons are:
1 receiver member/method/property (including enum/static classification),
2 implicit `this`/`base` receiver, 3 contextual aggregate field initializer,
4 match variant/payload selection, 5 compiler-recognized intrinsic call,
6 the contextual `slots` initializer of a syntactically declared owner-slot field.
An ordinary undeclared `slots` value is still an error. These need the subsequent checked type model.
Types nested in these constructs and direct receiver value names are still bound.
Generic legality, constants' values, ownership, effects, ABI metadata selection
and constructor viability belong to subsequent checking; syntactic metadata
keys/strings are not language symbol references. Unknown ordinary names fail.

Run the explicit external qualification:

```sh
python3 -B tests/selfhost-binder/run.py --compiler /absolute/path/to/astrac \
  --build "$HOME/Workspace/codex/work/astra/build/selfhost-binder-4" \
  --runtime "$HOME/Workspace/codex/work/astra/runtime/binder-component"
```

The runner freezes independent annotated byte-span expectations before native
execution, retains actual unchanged C0 `--tooling-index` output, and compares
its common declaration/reference projection. C0 does not emit type-use edges,
namespace/import identities or generic templates in that projection. Checked
semantic detail strings and receiver-dependent target edges are outside parity.
C0 materialized generic names are projected to their template head while keeping
the original exact source ID. Its synthetic foreach index and exception staging locals at reserved keywords
are excluded; the actual source binding remains checked. Caller-information string
targets bind earlier required formals; metadata policy names are compiler policies.
`generate-walk.py --check` verifies the typed child scheduler against the schema.
Later C0 semantic failures remain separately classified, with independent binder
expectations. All first failures, commands, hashes, timings and memory logs stay
in external attempt directories. Build reuse requires complete source/tool/flag/
dependency/product identity; tests execute freshly. Runtime includes parsing,
allocation, IO and observation, not isolated lookup throughput. Hash probing has
no adversarial worst-case constant bound; lexical lookup follows scope depth,
and unqualified imported lookup visits that unit's import list. Parser import
validation retains its existing possible quadratic behavior. No global linear
complexity or speedup claim is made.
