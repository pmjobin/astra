# Native exceptions

This is the current bounded implementation; qualification is recorded separately.

The opt-in [UTF-8 message factory](utf8-messages.md) uses this same checked
channel for ordinary `InvalidUtf8` errors. Invalid bytes allocate no message;
the error's static diagnostic content is copied through the existing Error
snapshot constructor. Allocation exhaustion remains fatal on both paths and
adds no checked recovery or fatal-path unwind guarantee.

```astra
[ExceptionRoot]
class Error {
	readonly string text;
	init(string text) { this.text = text; }
	virtual property string message { get { return this.text; } }
}
class DecodeError : Error { init(string text) : base(text) {} }
void decode() throws DecodeError { throw new DecodeError("invalid input"); }
int main() {
	try { decode(); } catch(Error error) {
		if(error.message == "invalid input") { return 42; }
	}
	return 1;
}
```

Normal calls have no prefix try. Catch order selects the first compatible dynamic subtype. A catch after an earlier ancestor catch rejects. Declared bounds are open: catching known descendants does not exhaust a function declared `throws Error`. Concrete known bounds also work on generic free functions; abstract effect parameters are absent.

A catch binding is a non-owning borrow. It cannot be rebound, moved, released, returned as an owner or stored as an escaping alias. Ordinary mutable payload fields are not transitively frozen by catch. Bare `throw;` transfers its nearest catch owner and retains the original origin. `throw new DecodeError(...)` and `throw move ownedHeapError` transfer one dynamic object. Lexical/caller-backed objects and borrowed catches cannot become thrown owners.

The root annotation resolves exactly one ordinary class with a virtual get-only string message property. Names alone have no authority. `lib/astra/base/errors.astra` supplies the normal library root; applications may instead provide a qualified user root. No outcomes source is required. Result.Error is an ordinary variant, requiring an explicit source adapter if an application wants to throw a class exception.

A readonly string field owns an immutable counted snapshot. A get-only string property may return a literal/constant or its own initialized readonly snapshot. Inherited implementations and user overrides dispatch normally through Error. Helpers, recursive calls, allocation, I/O, mutable selection, setters and throwing accessors reject in this subset. Local receiver views and further local copies retain exact owner/extent loans. Equality, byte_length and noescape output may use them while every possible backing receiver lives. Assignments, loops and catches preserve backing alternatives. Releasing, moving, rearming or throwing a backing owner while its loan survives rejects. An inner scope can end its own views while outer views remain active. Creating another readonly snapshot explicitly copies independent storage.

Private checked calls publish successful values only on their null-exception edge. The existing void, scalar/vector, string, record, copyable enum, primitive/record owned arrays, heap-origin object pointers and owning enum result groups remain complete groups. Ignored successful owners are cleaned. Ordinary C exports must catch and map exceptions explicitly; foreign throws declarations reject.

`throws`, `throw`, `try`, `catch` are newly reserved. `new`, `virtual`, `override`, `readonly`, `base` are contextual additions. Error, RuntimeError, message, what and ExceptionRoot remain ordinary identifiers. Literals, escapes, interpolation, formatting and output APIs retain their prior contracts.

An ordinary `owned Error make() throws Error` may return a heap object via
`return move local;` or forward another heap factory. Owned heap parameters
consume that same original allocation and perform dynamic destruction when
their responsibility ends. Declared base results can carry derived heap objects
without slicing. The complete source program resolves a consistent heap or
legacy caller-backed domain for each ownership signature; mixing domains
rejects. The old `C.init` storage and its exact forwarding rules are preserved.
