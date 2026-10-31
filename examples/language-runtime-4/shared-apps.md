# Native shared application witnesses A25–A27

These programs use the public `Shared<T>`/`Weak<T>` operations documented in
[ADR 0110](../../docs/decisions/0110-native-shared-weak-lifetime.md). They take
fixed deterministic fixtures and return zero after checking their observations.
The separately compiled C observer records application events with exact bytes.

| ID | Source | Behavior and expected output |
| --- | --- | --- |
| A25 | `shared-document.astra` | Document revision 4, checksum 173; three strong consumers preserve payload identity, release out of creation order, and destroy once. `1:4`, `3:4173`, `4:4173`, `5:4173`, `2:4`, each followed by LF. |
| A26 | `weak-subscribers.astra` | Two weak subscriptions upgrade while sequence 42 is live and return expiration after terminal strong release. `1:42`, `3:43`, `4:44`, `2:42`, `5:-1`, `6:-1`, each followed by LF. |
| A27 | `shared-diagnostics.astra` | Shared exact derived diagnostic retains native interface dispatch across clone/move and destroys derived then base. `1:9`, `3:9`, `5:37`, `6:47`, `4:0`, `2:9`, each followed by LF. |

Run `python3 tests/shared-1b/apps.py /absolute/path/to/astrac
/absolute/external/runtime/output` from the repository. The runner compiles the
observer with strict C11 diagnostics, builds each app through public `-O0`,
`-O1` and `-O2`, compares exits and complete output, hashes every product, and
runs unsuppressed Valgrind when installed. It records full commands, exits and
stdout/stderr in `checks.json`, and writes `result.json` only after all checks
pass. Generated products remain outside source Git.

The separate shared lifetime suite adds independent native allocation/free
counts, checked unwind, owned field captures, 10,000 interleavings, weak
backedge cleanup, and source refusals. A successful compiler invocation alone
does not qualify these applications.
