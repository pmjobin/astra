# Namespaces and explicit source files

The separate [native-unit profile](native-units.md) adds versioned interfaces and
independent producer/consumer objects. The namespace rules below also apply to
ordinary multi-source compilation.

Supply every source file explicitly:

```sh
astrac -O2 left.astra right.astra main.astra -o application
```

A source file can begin with one namespace declaration and any using directives:

```astra
namespace Left;
using Shared;

public class Record {
    private int value;
    init(int value) { this.value = value; }
    int read() { return this.value; }
}
internal int inspect(Record value) { return value.read(); }
public int measure(Record value) { return inspect(value); }
```

Another file can select the type or function explicitly:

```astra
using Left;
int main() {
    var a = new Record(7);
    var b = new Right.Record(9);
    return measure(a) + Right.measure(b) - 16;
}
```

`Left.Record` and `Right.Record` are distinct nominal types, even when their
fields match. Ownership, move, borrow, cleanup and private Class-field checks are
unchanged across namespaces and files. An internal top-level name is accessible
only within its exact namespace, including other supplied files in that namespace.
The default is public. `internal` controls declaration-name access; it is not an
opaque-type or separate-compilation boundary. Class `private` remains lexical to
its declaring Class, including when another Class shares its namespace.

Resolution checks lexical names and builtin types as before, then the current
namespace, explicit imports and the legacy global scope. Two imported public names
with the same short spelling require qualification. Using directives do not load
sources. Missing namespaces diagnose; cyclic using directives work because every
declaration is collected before body checking. File paths never create namespaces.
No namespace directives preserves the prior global multi-source program.

Namespace names are single identifiers. Qualified types (including generic
applications), `new Namespace.Type(...)`, free functions and constants are
supported. Import an enum's namespace to use its type/variant member syntax.
The executable entry remains global `int main()` or its existing argument form.

Explicit C exports in namespaces have a deterministic C symbol, for example:

```astra
namespace Left;
export(C) int identity(int value) { return value + 11; }
```

Its C declaration is `extern int astra_ns_4_Left_8_identity(int);`. Each component
is prefixed by its byte length, which prevents namespace separator collisions.
Global exports retain their original names. Imported C names retain the original
short C spelling unless `CCode(cname=...)` supplies an explicit symbol. Duplicate
physical C symbols reject; two namespaces do not create two C library functions.

`tests/modules-1/verify.py` checks source-order independence, owner fields and
moves, ambiguous/missing/internal/private failures, cyclic imports, legacy globals,
public O0/O2 execution and an independently linked C client.
