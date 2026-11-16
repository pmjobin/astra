# The Astra Language Reference

Development edition 28-A2. This Reference describes the implemented native Astra
profile at compiler source baseline `9f5dfce1a7dbaa8fba93e783762563add34a1948`.
The qualification target is GNU/Linux x86-64 with LLVM 23.1.4, at O0 and O2.
This is a versioned engineering document, not a released language standard.

The Reference distinguishes syntax representation, checked semantics and native
emission. A construct reaching the parser is not therefore executable. A source
contract admitted by the older bootstrap compiler is not automatically admitted
by the current Astra compiler. Current refusals remain explicit in the
[feature matrix](limits.md).

## Reading the contract

Rules prefixed `R-` identify the [evidence ledger](../books/rules.json). Each entry
binds implementation symbols and byte spans by SHA-256 and names positive and
negative controls. The ledger states conformance obligations; the external
qualification receipt establishes which obligations actually ran. Prose and a
successful HTML build supply no native execution proof.

“Specified” describes a contract in the admitted native domain. “Implementation
defined” identifies a bound or target choice for this edition. “Unsupported”
provides no valid native use of that form. “Unproven” provides no guarantee;
observed behavior alone must not become a normative promise. Failure to prove
a larger intended contract requires a PARTIAL result even if examples pass.

## Contents

- [Language profiles and source programs](profiles.md)
- [Lexical structure](lexical.md)
- [Types and numerical values](types.md)
- [Declarations and name resolution](declarations.md)
- [Expressions and evaluation](expressions.md)
- [Statements and control flow](control.md)
- [Records, classes and enums](values.md)
- [Ownership and cleanup](ownership.md)
- [Sharing, observers and stored borrows](shared.md)
- [Arrays, ranges and lazy collections](collections.md)
- [Generics and constraints](generics.md)
- [Text and formatting](text.md)
- [Errors and effects](errors.md)
- [Native ABI and runtime profiles](abi.md)
- [Grammar and parser boundary](grammar.md)
- [Limits, feature matrix and qualification](limits.md)

For a gradual introduction, read [The Astra Programming Language](../guide/README.md).
The generated [library API](../api/library.html) and [compiler API](../api/compiler.html)
provide resolved declarations rather than a second source grammar.

R-EDITION binds this interpretation to the driver's independent verification
stages. The [exception ledger](../release-exceptions.md) preserves distinct
historical provenance and release decisions. Both books remain canonical
Markdown; offline and print-friendly HTML are derived products.
