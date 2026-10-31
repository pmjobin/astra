# Language/runtime applications, version 3

These eight additional applications use the public hosted compiler. The
independent qualification recipe is `tests/language-runtime-3/corpus.py`; all
outputs, inputs and native products are placed outside the source tree.

| Program | Work performed | New finite facilities |
| --- | --- | --- |
| interface-dispatch | Runtime pricing policy across varied quantities | Borrowed interface and typed callable invocation |
| polymorphic-diagnostics | Render two diagnostic severities with UTF-8 messages | Virtual native dispatch and derived cleanup |
| callable-stream-transform | Transform arbitrary binary files with captured byte bias | Move-only callable environment, borrowed capture property and bulk file I/O |
| closure-ledger | Accumulate charges, including early return and checked failure | Owned callable capture, borrowed property, move and forwarding |
| c-record-bridge | Update a padded, wide-integer shipment record in independent C | Natural LP64 borrowed POD pointer ABI and public object export |
| c-callback-provider | Fold a varied sequence through synchronous C callback invocation | Typed named callback and borrowed POD environment |
| property-replacement | Replace a private document owner after validation | Borrowed property projection, consuming setter, uncached computation |
| composed-event-report | Read binary input, select a metric and write a folded report | Namespace, interface, callable, borrowed property and C callback |

`record-api.astra` is also consumed by a separately compiled GCC/Clang C client.
The harness checks exact outputs and destination bytes, input variation,
preserved destinations on file failure, native cleanup counters and unsuppressed
Valgrind results. Public O0/O2 is used for every application, with O1 for selected
dispatch and callback routes.

These examples do not demonstrate shared/weak ownership. Callable objects are
not bare function-address values, and C callbacks currently name an exact native
function over a scalar POD context rather than retaining an arbitrary closure.
