# Callback inputs through ordinary expressions

Adding an unused callback setter no longer invalidates a collection. Each IR
distinguishes a formal with no actual callers from an unknown external input.
Empty formal flow contributes no code value; it cannot ground an indirect call.
C entry parameters remain unknown, and opaque code storage and the native export
barrier retain their existing rejection rules.

A bounded expression matrix exposed missing Source/Core argument flow inside
integer conversions, array initializers and buffer-allocation counts. CFG's
actual call instructions rejected the mutating callback in those earlier
prototypes, preventing native emission. Source and Core now traverse these
operands, floating conversions, comparison chains, shifts, array/slice indices
and ranges, collection operands and owning producer/replacement expressions.
The retained intermediate receipts supply no Source/Core rejection credit.

The registered matrix covers eight expression families. Each has a valid callback
program and a counterpart that installs a mutating callback. All positives pass
O0/O1/O2 with unsuppressed Valgrind; each negative reaches the actual scoped-effect
diagnostic. The fixture also contains an unused mutating function, an unused
setter, local aliases, two type specializations and distinct instances. Acceptance
depends on actual code flow rather than rejecting every declared mutating body.

Three further independent mutations replace a callback argument with that
mutating function after destroying the predecessor representation. The Core
replacement is nested in an integer conversion. Core, CFG and SSA independently
reject and then accept the restored program.

Compiler `7c460e569f8ec71df553b0d91b5c333d7a32368e3c61e06a276b6fee7b27a0f7`
passes 109 source programs (1,854 checks, 327 memory runs), 199 negatives
(1,592 checks), 640 opaque-unit checks (141 memory runs), 197 structural proofs
and the new expression matrix (168 checks, 24 memory runs). Its actual Meson
registration also passes. The registry has 9,374 entries, adding exactly that
matrix registration. Full affected-registry and final G7 qualification remain
outstanding. Exact source, recipe, binary and receipt identities are in
`structural-generics-15-code-inputs.json`.

All prior proof bodies, negative specifications, historical negative files and
protected user state remain unchanged. The four pending fixture requests remain
pending. No milestone PASS or canonical report update is claimed.

The next native-unit reproduction uses an ordinary `Holder<T>` with a copied
payload and independent `map<Result>` method. Export currently rejects the
generic method prototype; `Holder<int>::map<int>` also fails selector parsing.
This is required work under ADR 0165, not a permanent exclusion. Implement closed
method selection, canonical tuple identity and declaration-only imported members;
native callback preconditions and the remaining G2–G8 gates still follow.
