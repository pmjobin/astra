# Native function and closure values

The current [structural generic and callable contract](structural-generics.md)
adds qualified copied-record/owned/borrowed channels and closed generic
environments. The scalar-only initial profiles below retain their original
component scope. Signature identity, explicit environment ownership and checked
Error channels remain authoritative in both profiles.

Use an exact function signature to transport a named native function:

```astra
int double_value(int input) { return input * 2; }
Fn<int,int> choose() { return double_value; }
int apply(Fn<int,int> function, int input) { return function(input); }
int main() {
    Fn<int,int> function = choose();
    return apply(function, 7);
}
```

The first type argument is the result, followed by zero to four parameters.
Numeric scalars and bool are supported; exact widths and signedness must match.
These signatures are nonthrowing. Checked, owning, aggregate and foreign
function signatures are refused. Copying an `Fn` copies its native code address
and requires no heap environment.

For an explicit owned environment, construct an exact heap Class and transfer
it to `closure_bind` with a named native function whose first parameter borrows
that Class. The remaining parameters and result use copied scalars:

```astra
class Offset {
    int amount;
    init(int amount) { this.amount = amount; }
}
int offset_code(borrowed Offset environment, int value) {
    return environment.amount + value;
}
int main() {
    var environment = new Offset(10);
    var function = closure_bind(move environment, offset_code);
    return closure_invoke(function, 7);
}
```

`Closure<Offset,int,int>` is a linear owning handle. Its carrier contains native
code, the owned environment and its exact destructor code. Move or return it
through an `owned` boundary; use a `borrowed` parameter for temporary invocation.
Scope exit, early return and checked unwind release the carrier and environment.
The environment may own unique children or explicit shared/weak handles under
their existing transfer rules. A call cannot consume its own backing closure
while evaluating scalar arguments.

A throwing target uses an explicit, distinct signature:

```astra
int checked_offset(borrowed Offset environment, int value) throws Error {
    if (value < 0) { throw new Error("negative offset"); }
    return environment.amount + value;
}
int use_checked() throws Error {
    var environment = new Offset(10);
    var function = checked_closure_bind(move environment, checked_offset);
    return closure_invoke(function, 7);
}
```

The inferred type is `CheckedClosure<Offset,Error,int,int>`. Its second type
argument is the exact declared error bound; the remaining signature follows
Closure. An indirect call requires a compatible `throws` declaration or catch.
The native call carries the ordinary checked exception and private scalar
success channels. Catching an error preserves the borrowed closure for another
invocation; exiting its owning scope destroys it normally. An ordinary Closure
or Fn cannot alias a CheckedClosure. C callback adapters must catch and record
failure, then let native code observe it after C returns.

The initial environment must be an exact nonpolymorphic, nongeneric heap Class.
General lambda inference, captured stack references, async transport, threaded
delegates and arbitrary foreign retention are unsupported. The explicit bounded
retained callback API is described by its separate contract. Existing
[nominal callable objects](callable-objects.md) remain available.
