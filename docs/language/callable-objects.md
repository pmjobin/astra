# Native callable objects

A native Class with a typed `invoke` method can be called as `function(args)`.
The call has the same signature, checked effects, receiver validation, dispatch
and ownership behavior as `function.invoke(args)`. This spelling supports direct
Class locals, heap owners and borrowed Class parameters. It does not convert
arbitrary data pointers to callable code.
Existing named free functions retain their call-name precedence when a local
shares that name; `value.invoke(args)` selects the object explicitly in that case.

```astra
class Offset {
	int value;
	init(int value) { this.value = value; }
	int invoke(int input) { return this.value + input; }
}
int twice(borrowed Offset function, int input) {
	return function(input) + function(input + 1);
}
int main() {
	Offset function = Offset.init(10);
	return twice(function, 15); // 51
}
```

Here `function` is a lexical environment. Calling or borrowing it does not
allocate, copy the object or transfer cleanup. A borrowed parameter remains
nonescaping under the existing native Class borrow rules. Captures are explicit
Class fields: copied scalars are snapshots, and an `owned Payload` field moves
the unique Payload into the environment. An environment created with `new` can
move or return through an exact owned Class result. Its destructor and captured
owner cleanup run once at the ordinary owner endpoint, including early returns
and checked failure. Capturing borrowed Class/Resource references in fields is
still rejected.

A zero-field lexical wrapper can call a named native function from another
namespace/source file without a heap allocation. This is an explicit nominal
function object. Bare function addresses, inferred lambdas, general delegate
types were outside this original callable-object slice. Native function values
and explicit owning closure carriers now have their separate
[typed value contract](first-class-callables.md). Captured stack-reference fields
and retained C callbacks remain unsupported. A nominal callable object alone
does not establish a first-class function-value contract.

The independent source/native checks are in
`tests/language-runtime-3/callable-check.py`; they cover public O0/O1/O2,
namespace transport, borrowed invocation, owner move/forwarding, early return,
checked unwind, exact C-observed cleanup traces, and invalid ownership/effects.
