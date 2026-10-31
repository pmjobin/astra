# Language/runtime applications 25–32

These applications exercise the finite native contracts from decisions
[0110](../../docs/decisions/0110-native-shared-weak-lifetime.md),
[0111](../../docs/decisions/0111-native-function-values.md) and
[0112](../../docs/decisions/0112-explicit-owning-closure-values.md).
Run the public qualification with `sh tests/language-runtime-4/verify.sh`.
It uses the coordinated external build area and checks the executable feature
inventory in `tests/language-runtime-4/features.json`.

| Application | Observable work | Protocol |
| --- | --- | --- |
| A25 shared document | Two consumers retain one document, observe identical identity and release in different orders | [shared applications](shared-apps.md) |
| A26 weak subscribers | Live notification succeeds; later acquisition reports expiration | [shared applications](shared-apps.md) |
| A27 shared diagnostics | Interface-dispatched derived diagnostics retain identity and destroy the dynamic chain once | [shared applications](shared-apps.md) |
| A28 function pipeline | Runtime-selected typed functions process command-line values with exact output | [pipeline](function-pipeline.md) |
| A29 message transformation | An owning closure captures unique/shared state, generates UTF-8 and forwards ownership | [closure applications](closure-applications.md) |
| A30 checked rollback | Failure after capture/upgrade leaves the outer strong owner valid and cleans captures once | [closure applications](closure-applications.md) |
| A31 synchronous events | A C provider feeds events through typed native transforms and verifies callback order | [event bridge](sync-event-bridge.md) |
| A32 observer report | Bulk file input becomes transformed records and a deterministic UTF-8 file report | Below |

`observer-report INPUT OUTPUT BIAS` accepts up to 64 input bytes and a bias in
0..1000. Each output record is `INDEX:VALUE\n`, where VALUE is twice the sum of
the byte and bias. A final line reports record count, total and observed weak
expiration. For bytes 0, 7, 128, 255 and bias 3, output is:

```text
0:6
1:20
2:262
3:516
records=4 total=804 expired=1
```

The closure retains a shared interface implementation and a weak observer. It
uses a bare function value during transformation. File input passes through an
existing private borrowed property; exact heap row objects remain in a Bag
until report completion. Releasing the closure retires the payload, and a later
weak upgrade observes expiration. The C observer checks payload/row cleanup.

The report protocol checks O0/O1/O2, empty and maximum inputs, exact file bytes,
missing input, failed output acquisition and invalid input. Exit 0 means a
written report, 64 means invalid bounds/arguments, and 2 means checked parse or
file failure. Cleanup invariant failures have separate exits 3/4. All runtime
products and receipts stay outside the source repository.
