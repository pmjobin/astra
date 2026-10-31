# ADR 0090: Native class exceptions and Error.message

**Direction:** USER_APPROVED by the submitted ASTRA-ERROR-1 native-exceptions starter and its verified USER-DIRECTION.md, replacing the never-approved enum E3 implementation draft.

**Implementation:** ERROR-1-R1 completes the bounded source and verification slice; final qualification and external review remain separate gates. See R1 validation scope.

An exception is an owned native object derived from one explicitly nominated ordinary `[ExceptionRoot]` class. The library supplies `Error` and `RuntimeError`; user classes use the same allocator, single-inheritance layout, fields, constructors, destructors and virtual property machinery. Enums and Result remain ordinary values. There is no automatic bridge, Outcome registration, capture coupling or prefix try on ordinary calls.

`throws Class` states an open checked subtype bound. Protected blocks have ordered ancestor catches; a catch borrows the dynamic object. Fresh construction and `throw move owner` transfer heap ownership. Bare throw transfers the nearest lexical catch owner with its original identity and origin. Handlers do not catch exceptions from their own bodies or sibling handlers. Overrides may narrow or remove an inherited throws bound.

`Error.message` is an ordinary get-only virtual string property. Its bounded getter subset is a literal/constant or an initialized readonly string snapshot. Snapshot creation copies the exact counted UTF-8 bytes, including NUL, before the input borrow ends. Retrieval performs no allocation, release, mutation or I/O and retains receiver lifetime authority. Stored receiver views and copies carry exact owner/extent loans through merges, loops and handlers. Receiver invalidation rejects while a loan survives; explicit snapshot construction creates independent storage.

The [recorded ABI plan](../abi/native-exceptions.md) uses a private nullable owned exception channel, complete caller success storage and generated cleanup edges. A logical virtual slot has an ordinary entry and a checked entry; a nonthrowing override uses a checked-channel adapter. The channel does not unwind through C. Allocation exhaustion and existing traps remain fatal.

Reusable prerequisites are bounded: explicit `new C(args)`, stable unique heap ownership, zero-offset complete base layout, explicit base initialization, inherited fields and borrowed upcasts, virtual methods/properties and derived-to-base destruction. Heap-origin factories and owned parameters are included with distinct verified origin contracts beside preserved caller-backed storage. Shared ownership, owning child objects, general property lifetimes, reflection and TEXT-OWN-1 remain later work.

[ADR 0087](0087-shared-enum-and-error-foundations.md) remains historical. Its enum-backed checked errors, mandatory A+C and explicit-only async proposals are superseded where inconsistent. ADRs 0088/0089 and completed ordinary enum ownership contracts remain intact. Revised exception-based async is the next source milestone after ERROR-1 acceptance and is not implemented by this decision.
