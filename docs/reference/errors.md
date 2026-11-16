# Errors and effects

R-ERRORS. Recoverable errors use an explicit nominated exception root. The
selected library's `[ExceptionRoot]` declaration establishes `Error`; the source
file is part of the compilation, not a compiler-injected global package.
A function declares `throws Error` or its admitted bound. A throwing call must
be handled or propagated by a compatible effect contract.

`throw new Error(...)` constructs an owning error under that contract. A
`catch (Error error)` binding observes the caught error for the handler's
lifetime. Error text and class payloads require their declared backing. A catch
does not manufacture an escaping borrowed message result. Error/result channels
are checked before native effect ABI lowering, rather than inferred from a C
return convention or a raw pointer shape.

R-ERROR-CLEANUP. Normal results and errors have distinct live storage/cleanup
paths. Temporaries, owned arguments and partially established storage must retire
according to the selected path. A return or rethrow cannot duplicate retirement
of the caught owner. The current ownership/error regressions exercise failed
operands, owned results and caught cleanup, with strict returning memory checks.

The Guide's [error program](../guide/text-errors.md) calls a validator that rejects
a negative reading, checks the exact caught message and returns the expected
success code from its handler. It does not claim that every class hierarchy,
foreign error policy or asynchronous throw bridge is supported.

## Recoverable versus fatal

R-FATAL. Fatal allocation behavior and runtime traps are separate from
recoverable errors. An allocation contract may explicitly provide a failure
action; lack of memory is not automatically catchable as this language's `Error`.
Bounds/invalid-operation traps do not promise stack unwinding or destructor
execution. Testing a normally returning path cannot establish all cleanup after
process termination.

`finally` and larger historical exception surfaces require exact current native
admission before use. The source parser and effect model retain more forms than
every native recovery path can lower. This edition grants no general `finally`
or asynchronous error framework guarantee. The precise E25-A-v1 approval and
independent effect/source/owner boundaries remain unchanged by documentation.
Use the [ABI chapter](abi.md) and [limits matrix](limits.md) when deciding whether
a source effect is in the qualified native domain.

## Handler scope and error storage

R-HANDLER-SCOPE. A handler covers the protected try body. Its own catch body
inherits the outer handler stack, so a throw from a handler is not recursively
caught by that same handler. Catch bindings refer to the actual caught owner;
borrowing its message is valid only while that owner/backing remains live.
Normal result storage and error storage are distinct ABI channels. A throwing
call's result may be loaded only on its success edge.

A derived Error retains the approved exception header before its own fields.
Construction initializes the base before own-field statements. Destruction
retires own fields before the parent chain, and dynamic destruction frees the
object once after that chain returns. These facts have separate
[source/layout](../../compiler/semantic/recover-error-layout.astra),
[CFG error movement](../../compiler/cfg/recover-error-move.astra) and
[physical destruction](../../compiler/backend/llvm/recover-error-check.astra)
consumers. An ordinary class payload must not be substituted for Error storage.

Empty owning Error values are permitted in admitted ordinary channels; throwing
an empty error takes a fatal guard rather than dereferencing an absent header.
This supplies no guarantee of cleanup on process termination. The
[call-abort teaching program](../guide/text-errors.md#cleanup-when-a-later-argument-fails)
checks only returning success/handler paths, with exact destructor observations
and strict memory. The scope is synchronous native execution; general historical
async/error bridges and `finally` are not promoted by these observations.
