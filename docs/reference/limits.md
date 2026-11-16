# Limits, feature matrix and qualification

R-LIMITS. This edition binds exact native products and preserves the generic
instance limit of 256 and SSA work ceiling of 8,000,000. Parser expression
nesting is bounded at 256; other source/type/storage budgets retain their own
checked limits. A resource refusal is not undefined execution or permission to
increase a bound. Optimized compilation must retain independent source/owner and
physical verification before LLVM optimization and its own structural checks.

## Supported and unproven features

R-MATRIX. “Covered” means an explicit fixture or named current regression is
part of the campaign; actual run status belongs to its qualification receipt.
It is not a statement that every imaginable combination is supported.

| Area | Current native contract | Boundary |
| --- | --- | --- |
| Scalars | Exact integers, bool, f32/f64 and checked conversions | No implicit promotion or arbitrary precision |
| Declarations | Explicit files, namespaces, exact nominal types and checked locals | No automatic package resolver or overload system |
| Control | if, while, conditional expressions and admitted integer-sequence foreach | Representative for and comparison chains refuse in Flow |
| Records/classes | Copyable records, admitted native classes, methods and checked field getters | Arbitrary property/inheritance shapes require separate admission |
| Ownership | Unique/shared/weak, owning channels, stored-borrow checks and cleanup | No owner-copy or escaping loan guarantee |
| Generics | Concrete checked instances and bounded capabilities | 256 instances; not all parsed generic bodies lower |
| Enums | Exact variants, exhaustive nested matches and admitted ownership payloads | No arbitrary enum C layout or reflection |
| Ranges | Exact integer bounds, positive strides, checked ends and collection | No floating ranges or generalized iterator protocol |
| Arrays/views | Owning/fixed arrays and immediate readonly range views | Retained range-view descriptors refuse |
| Lazy collections | Admitted map/filter/sum/materialization and bounded comprehension | No escaping coroutine or arbitrary owned capture |
| Text/errors | Explicit UTF-8/runtime selection, typed immediate formatting and recoverable errors | No generic Unicode ecosystem or automatic catchable OOM |
| C | Selected scalar, opaque and counted text/buffer channels | Arbitrary policies, callbacks/frameworks unproven |
| Freestanding | Selected scalar/fixed-array Linux x86-64 syscall programs | No general firmware or cross-platform qualification |
| Vector/typed pointers | Represented by frontend | Simple native programs below refuse in Flow |
| Constants | Represented by frontend | Representative top-level use refuses in Flow |
| API metadata | astra-api-docs/1 resolved declarations | Namespace/variant declaration TypeIds unproven; owner/payload contracts remain distinct |
| Async/concurrency | Historical sources and policies remain available for review | No new current native framework qualification in this campaign |

The following are negative programs. They establish an honest current boundary,
not a specification for future SIMD or pointer semantics:

```astra example=negative-vector
language astra27b;
int main() {
	i32<2> values = {20, 22};
	return values[0]+values[1];
}
```

```astra example=negative-pointer
language astra27b;
int main() {
	int value = 42;
	int* pointer = &value;
	return *pointer;
}
```

## Evidence and remaining editorial obligations

R-QUALIFICATION. [Rules](../books/rules.json) map chapter assertions to hashed
source spans and positive/negative controls. [Inventory](../books/inventory.json)
lists source units and syntax families; unreviewed families remain explicit.
The grammar chapter is a parser-aligned summary, not an independently complete
formal specification of every represented policy. A lack of exhaustive coverage
must therefore keep G1/G2 PARTIAL until reviewed and tested, even when the two
books are readable and their examples pass. The books must not narrow that
acceptance condition to the size of their current fixture set.

## History and later milestones

R-HISTORY. Original C0 and 1,044 historical raw proof files remain absent.
Milestone 27-B remains PARTIAL. The owner accepted authenticated rebuilt-C0
provenance substitution WITH DISCLOSURE; rebuilt C0 strict all-kinds process
memory remains NOT_PASS. Provenance acceptance does not waive contemporary
safety or settle release risk. See the [exception ledger](../release-exceptions.md)
and [owner decision](../decisions/0170-rebuilt-c0-release-provenance.md).

28-A1's immutable report retains its original G7 pending status; the separately
dated real after-publication receipt is distinct. 28-A2 likewise leaves G8
pending until its actual report exists. Performance/C++ comparisons are 28-B,
developer experience 28-C, and release qualification 28-D. Print production is
later Markdown-derived work. These books claim no PDF, hardback, deployment,
RC, public tag or final release.
