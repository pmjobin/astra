# Reconciliation format, version 1

This schema is frozen before implementing the challenge output. The requirements
in docs/structural-generics-15-reconciliation-challenge.md remain binding.

The CLI receives decimal integer arguments: a stock count N, then N groups of
`warehouse sku quantity unit-cost`, then zero or more groups of
`warehouse sku delta expected-revision reject-audit`. A key is the exact copied
pair `(warehouse, sku)`. Initial revisions are zero. Initial duplicate keys,
negative quantity/cost, malformed arguments and values outside signed 32-bit
range are input errors (exit 2, no report). Warehouse and SKU may be negative.
Reject-audit must be 0 or 1. Inventory arithmetic has an explicit signed 32-bit
limit; intermediate calculations must be checked before committing.

Output is ASCII TSV with decimal integers and a final LF for every row:

- `astra-reconcile<TAB>1`
- `decision<TAB>index<TAB>warehouse<TAB>sku<TAB>delta<TAB>expected-revision<TAB>outcome<TAB>quantity<TAB>revision<TAB>value<TAB>accepted<TAB>attempts`
- `stock<TAB>warehouse<TAB>sku<TAB>quantity<TAB>unit-cost<TAB>revision<TAB>value`
- `summary<TAB>changes<TAB>accepted<TAB>attempts`

Decision indices start at one. Outcomes are `accepted`, `unknown`, `stale`,
`overdraw`, `overflow`, or `audit-error`. Unknown keys use -1 for quantity,
revision and value. Other decisions show the inventory state after the decision.
Accepted and attempts are global callback counters after each decision.

Validation precedence is unknown key, stale revision, negative proposed quantity,
then overflow (quantity, revision or quantity times unit cost). Invalid changes do
not call the audit. Valid proposals call it once; injected rejection increments
attempts and raises a checked error without incrementing accepted. A later change
with the same key/delta/revision and rejection cleared retries through the same
live callback environment. An accepted proposal increments accepted, returns a
typed receipt containing that sequence and proposed value, and commits exactly
once after checking the receipt. Initial quantity times unit cost must also fit.

Decisions retain input order. Final stocks sort by signed warehouse then signed
SKU. A run containing rejected changes still returns exit 0 if processing and
reporting complete. Unexpected runtime or output errors return exit 4.

A Python reference will compute this protocol directly from the input arguments.
It must not derive expected output from observed Astra results. Exact cleanup and
opaque native-library execution require separate evidence beyond this format.
