# ADR 0006: Separate checked semantic model

Status: accepted in ASTRA-SEM-1, on the ASTRA-PARSE-1 foundation.

## Decision

1. Astra maintains a checked semantic model distinct from its syntax tree.
   `SemanticAnalyzer` consumes a parsed compilation unit and returns either a
   complete `CheckedProgram` or a source diagnostic. Analysis does not mutate
   syntax nodes into semantic objects.
2. Source and syntax objects remain authoritative for spelling and provenance.
   Checked nodes and symbols retain source spans; spans retain the source file.
   Integer literal spelling is read from those bytes without host conversion.
3. Semantic type identity is compiler-owned and does not use LLVM types.
   `BuiltinTypes` provides canonical `SemanticType` objects for `int` and `void`
   within each analysis/checked program. Type checks compare those identities.
4. Name resolution produces references to semantic entities. In this subset,
   a checked parameter reference holds its exact `ParameterSymbol`, rather
   than a name that downstream consumers must resolve again.
5. Semantic analysis occurs before Core IR construction. Function signatures
   are collected and checked before any function body is analyzed.
6. Physical representation, ABI, and LLVM lowering are downstream concerns.
   Semantic types have no layout, size/alignment, or LLVM conversion APIs.
7. The checked model may discard purely syntactic distinctions that have no
   semantic meaning while retaining source provenance. Parentheses disappear
   after parsing has established grouping; the checked inner expression keeps
   its own span. The unchanged syntax tree still records the parentheses.

## Rationale and scope

A distinct checked model lets consumers use resolved types, symbols, and
semantic operator enums without reinterpreting syntax tokens. Keeping source
spans preserves diagnostic locations and exact literals without requiring the
checked model to retain every punctuation node. Types, symbols, checked nodes,
and the semantic dump depend on the source layer, not syntax classes; the
analyzer alone translates syntax into semantic objects.

Canonical types belong to a checked program's analysis, with no process-global
mutable registry. Symbols and expressions retain their type objects. A function
owns its ordered parameter symbols, and checked references also retain their
parameters. No parameter-to-function back reference is needed for this grammar,
so the retained object graph has no such cycle. Ordinals are zero-based within
each function and are assigned in declaration order.

The type authority resolves exactly `int` and `void`; both remain identifiers in
the lexer. Function declarations and function-local parameter names have
separate lookup tables. This implements the current grammar without settling a
full namespace or nested-shadowing policy. Duplicate function names are rejected
because overloading is not implemented, including when signatures differ. That
restriction does not establish Astra's permanent overloading policy.

`int` is an Astra language type for the current integer expressions. This
decision freezes no physical width, target/host representation, ABI, overflow
mode, wrapping/checking policy, or literal range. `void` denotes a function
returning no value and cannot type a parameter. There is no constant folding,
implicit conversion, definite-return analysis, or unreachable-code analysis.
No other types or later compiler stages are introduced by this decision.

`src/semantic/` and its Meson dependency use only the source/syntax frontend and
existing GLib/GObject host dependencies. The semantic test executable and driver
do not import or link the LLVM backend. Where `ldd` and `nm` are available,
automated tests inspect these executables and the syntax test executable for
LLVM linkage/backend symbols, with the separate LLVM smoke fixture as a negative
control. Strict C pointer checks and PARSE-1 tests remain in place.

See the [implemented semantics](../language/semantics.md) for rules and the
internal checked-model dump. This decision does not design a full type system.
