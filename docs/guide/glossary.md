# Glossary, index and edition history

Use this index when a program compiles but its responsibility or cost is unclear.
The linked Reference chapters define the corresponding rules. The complete-book
HTML routes support browser Find over all chapters without a search service or
JavaScript. Printed/print-preview reading uses the same canonical source order.

| Term | Meaning and destination |
| --- | --- |
| Acquisition | Establishing one cleanup responsibility; [ownership](../reference/ownership.md) |
| Borrow | Access without new cleanup responsibility; [sharing](../reference/shared.md) |
| Capture | Retaining a checked value for later lazy work; [collections](../reference/collections.md) |
| Counted string | UTF-8 bytes plus a length, possibly containing NUL; [ABI](../reference/abi.md) |
| Exact type | Checked identity rather than an implicit numeric conversion; [types](../reference/types.md) |
| Extent | Fixed or runtime element count; [sequences](sequences.md) |
| Instance | Concrete checked generic specialization; [generics](../reference/generics.md) |
| Materialization | Making actual owning/fixed storage from a sequence; [collections](../reference/collections.md) |
| Move | Transfer of responsibility with source invalidation; [owners](objects.md) |
| Nominal | Identity from a declaration rather than matching fields; [records](../reference/values.md) |
| Physical verification | Independent source/native correspondence checking; [ABI](../reference/abi.md) |
| Profile | Per-source language choice or explicit runtime/target scope; [profiles](../reference/profiles.md) |
| Rule ledger | Hashed source spans and named positive/negative controls; [ledger](../books/rules.json) |
| Sentinel | Existing output bytes that a refusal must preserve; [tooling](tooling.md) |
| Weak observer | A handle that does not keep its payload alive; [sharing](../reference/shared.md) |

## Edition 28-A2 changes

This edition adds the Reference and progressive Guide to the existing chapter
manifest, exact source fixtures, current-native boundary examples, a multi-file
file-processing application, source/rule inventory, offline navigation and
print-friendly HTML. It reuses `astra-api-docs/1` and the existing safe API
renderer. Canonical source remains Markdown; generated builds stay outside Git.

The declared completion standard remains larger than “all examples pass.”
Incomplete source/rule coverage, major unqualified chapters or acceptance gaps
require PARTIAL. [Limits](../reference/limits.md) identifies remaining grammar and
coverage obligations, and the campaign report records actual gates and timings.

## History that remains visible

Original C0 and 1,044 historical raw proofs remain missing; 27-B stays PARTIAL.
The owner accepted authenticated rebuilt-C0 provenance substitution WITH
DISCLOSURE, while its strict all-kinds process memory remains NOT_PASS.
Contemporary safety receives no waiver. Read the [exception ledger](../release-exceptions.md)
before treating these books as release material. Separate later work covers
28-B performance/C++ comparisons, 28-C developer experience, 28-D release
qualification and Markdown-derived professional print production. This edition
claims no deployed website, final PDF, hardback, RC or release tag.
