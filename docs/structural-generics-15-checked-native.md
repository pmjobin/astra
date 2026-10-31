# Checked native calls and shared class descriptors

Native units now carry checked scalar/record calls with their exact exception
bound and nominated root. Exported polymorphic classes publish an immutable
descriptor; importers reference that descriptor through its pinned external
symbol. Consumers no longer create a second private identity for an imported
exception class. Parent relationships, virtual slot identities, root flags and
counted text snapshot storage participate in the class layout contract.

The ordinary read-only string error message, its virtual getter and constructor
text parameter use existing counted text ABI plans. Declaration-only getters
pass each IR's original native-signature verifier. Producer getters retain their
body checks; an imported declaration does not supply a consumer implementation.
LLVM verifies descriptor symbol, concrete global type, linkage, immutability and
the exact initializer or its required absence for an import.

The new leaf/middle/client chain returns a copied generic record, raises a
derived exception through both libraries, catches its concrete type and retries
successfully. The client imports only the middle. A client-defined subclass
overrides the text getter; the leaf invokes that implementation through the
imported root's virtual contract. Producer implementation copies are deleted
before consumer compilation. All eight mixed O0/O2 combinations and O1 pass with
nine unsuppressed memory runs and complete retirement of the text snapshots and
exception objects.

Forged descriptor symbols reject during artifact validation. A forged declaration
narrows the error bound while retaining the original physical signature and
object; independent signature reconstruction rejects it before unsafe emission.
Three further Core/CFG/SSA mutations change a native declaration's error bound
after destroying the preceding representation. Each stage rejects the mismatch
and accepts the restored program.

Compiler `5702a31de07fc9cbb96fe704746260fc49795c7d28e836a360dac94e0fd4277a`
passes 109 source programs (1,854 checks, 327 memory runs), 199 negatives
(1,592 checks), 715 opaque-unit checks (159 memory runs), the expression matrix
(168 checks, 24 memory runs), and all 203 structural proofs. Exact source,
recipe, binary and receipt identities are in
`structural-generics-15-checked-native.json`. These are focused increment results;
the affected registry and final G7 have not been rerun.

The retained initial root probe lacked the required virtual message property.
Another early client discarded a record result without an allowed consumer.
Neither invalid source supplies native acceptance credit. The first forged-bound
test hashed escaped KeyFile text; its declaration-digest rejection supplies no
bound-checking credit. The corrected test decodes newlines and reaches the actual
native signature mismatch.

The next valid reproduction passes a borrowed CheckedClosure with an explicit
generic environment and copied-record input/result across a unit. It currently
fails the public parameter profile. Complete callable facts, ordinary interface
exports, actual native async suspension/cancellation, scoped callback
preconditions, the useful application and remaining G2–G8 qualification are still
required. Historical fixture expectations remain unchanged; no milestone PASS
or canonical report update is claimed.
