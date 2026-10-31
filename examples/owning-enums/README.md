# Explicit owning outcomes consumer

Select these four files and `lib/astra/base/outcomes.astra` together. The source
order is immaterial. The consumer exercises a copied Header result, a zero-field
VoidResult, nested error handling, generic int/u8/record array production and
forwarding, readonly inspection and consumption into independently owned arrays.
Outcomes have ordinary enum
semantics; checked errors and async are separate language features.
