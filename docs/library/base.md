# Opt-in Astra base library

DIAG-1 adds separately selected [source-aware assertions](source-diagnostics.md)
in `base/diagnostics.astra`, using reusable native caller-information parameters
and one explicit diagnostics provider. Captured paths/snippets may disclose
private data. Legacy assertions, equality APIs and provider signatures are unchanged.

Programs may independently select [validated process arguments](../language/process-arguments.md) by linking `args-posix.o`. It adds one private startup allocation and no automatic library sources. BASELIB and hosted output remain separately selected; installation paths follow configured datadir/libdir and target.txt.

The [named-constant consumer](../../examples/base/constants.astra) uses exact
compile-time dimensions and thresholds, inferred min/max/clamp calls, explicit
numeric conversions, owned buffers and always-on assertions. Compile it with
`base/order.astra`, `base/classify.astra`, `base/contracts.astra`, `base/clamp.astra`,
`--vapi hosted/math.vapi`, one selected failure provider through `--link-object`,
and `--link-library=m`, using the installed paths described in this guide. Library functions
remain ordinary runtime functions and cannot initialize a constant.

The library is source code you select explicitly. It works with the accepted
GEN-INFER-1 language and does not introduce a prelude, module system or compiler
intrinsics. This source fragment uses ordinary inferred generic calls:

```astra
var bounded = clamp(value, 0.0d, 1.0d);
assert(is_finite_f64(bounded));
var root = sqrt_f64(bounded);
```

## Components and dependencies

| Select | Public functions | Dependencies |
| --- | --- | --- |
| `base/order.astra` | min, max | None |
| `base/slices.astra` | fill, swap_elements | None; ordinary checked-index traps |
| `base/buffers.astra` | clone_array, filled_array | Explicit slices.astra, including clone-only clients; existing hosted buffer allocation |
| `base/outcomes.astra` | Result<T,E>, VoidResult<E>, ArrayResult<T,E> | Ordinary explicitly selected enums; ArrayResult uses the existing allocator/free only when constructing owned arrays |
| `base/classify.astra` | is_nan/is_finite/is_infinite, each `_f32` and `_f64` | None |
| `base/contracts.astra` | assert, assert_code | Exact I32 C import astra_base_fail |
| `base/diagnostics.astra` | assert_that, assert_message | Exact borrowed utf8-i32 astra_diag_assert_fail_v0; choose diagnostics-trap.o or diagnostics-hosted.o |
| `base/clamp.astra` | clamp | contracts.astra for the shared failure declaration |
| `failure-trap.o` support object | Failure provider | Qualified hardware trap; no runtime symbols |
| `failure-hosted.o` support object | Alternative failure provider and equality reporters | Hosted libc/stdio/abort/memcpy |
| `hosted/equality.astra` | assert_equal_i32/f32/f64 | Hosted provider, CABI-FP target qualification |
| `hosted/math.vapi` | sqrt/floor/ceil/trunc/abs, each `_f32` and `_f64` | Explicit libm, CABI-FP target qualification |
| `hosted/text.astra` | print, println, print_stderr, println_stderr | Explicit text-posix.o; text-view-v3 x86-64 Linux qualification |

Providers are alternatives. Select exactly one when using contracts. Equality
assertions require the hosted provider, which also implements the core hook.
The [text output provider](text-output.md) is independently selected and can
coexist with either failure provider. It reports ordinary output failures as
false and never calls the failure hook. Its header/source install with the
platform sources; its object installs beside target.txt under the configured
libdir. Installation and relocation tests discover prefix/datadir/libdir from
Meson options.
The optional [array-production source](array-production.md) acquires new array
owners using the accepted BUFFER allocator (`calloc`/`free`). Other base sources
retain their existing allocation contracts. Compiler GLib/GObject/LLVM
dependencies never become emitted-program dependencies.

There is no private/module visibility. Library and user definitions participate
equally in ordinary SOURCES-1 duplicate diagnostics. Legacy helpers and adapter
symbols use `astra_base_`; the new diagnostic hook uses `astra_diag_`. These are
documented conventions only. Public names
are provisional and are not keywords.

`base/outcomes.astra` is opt-in ordinary source. `Result` carries copied scalar,
record or eligible copied enum values; `VoidResult` has a zero-field Success;
`ArrayResult` carries a unique owned array. Explicit constructor/pattern arguments
and whole-owner `move` apply exactly as for differently named user enums. E is a
copied error value and need not be zeroable. These names provide no checked-error
propagation, implicit import or runtime handler. E2 implementation qualification
is partial.

The installed four-source [owning consumer](../../examples/owning-enums/README.md)
uses Header/error values, generic production/forwarding, readonly inspection and
consuming extraction. Select `types.astra`, `produce.astra`, `consume.astra` and
`main.astra` from `share/astra/examples/owning-enums`, together with
`share/astra/base/outcomes.astra`. The ordinary command is:

```sh
astrac types.astra produce.astra consume.astra main.astra /chosen/prefix/share/astra/base/outcomes.astra -o consumer
./consumer
```

No assertion provider, output object or new dependency is required. The maintained
`tests/enum-own-1/client.py` discovers configured installation paths and validates
all 24 application orders from staged and relocated prefixes outside the checkout.

## Build and use in the source checkout

Run from the Astra checkout; all generated files stay under `build/`:

```sh
CCACHE_DISABLE=1 meson setup build -Dwerror=true
CCACHE_DISABLE=1 meson compile -C build
mkdir -p build/base-examples

build/astrac examples/base/pure.astra lib/astra/base/order.astra lib/astra/base/classify.astra -o build/base-examples/pure
build/base-examples/pure

build/astrac examples/base/contracts.astra lib/astra/base/order.astra lib/astra/base/classify.astra lib/astra/base/contracts.astra lib/astra/base/clamp.astra --link-object build/lib/astra/failure-trap.o -o build/base-examples/contracts
build/base-examples/contracts

build/astrac examples/base/diagnostics.astra lib/astra/hosted/equality.astra --link-object build/lib/astra/failure-hosted.o -o build/base-examples/diagnostics
build/base-examples/diagnostics

build/astrac examples/base/math.astra --vapi lib/astra/hosted/math.vapi --link-library m -o build/base-examples/math
build/base-examples/math

build/astrac examples/base/buffer/main.astra examples/base/buffer/model.astra examples/base/buffer/process.astra lib/astra/base/order.astra lib/astra/base/classify.astra lib/astra/base/contracts.astra lib/astra/base/clamp.astra lib/astra/hosted/equality.astra --vapi lib/astra/hosted/math.vapi --link-object build/lib/astra/failure-hosted.o --link-library m -o build/base-examples/buffer
build/base-examples/buffer
```

The combined example owns an f64 runtime array in a class, borrows it through
plain native parameters, transforms Vec2/Lab values, uses exact `d` literals and
explicit integer conversion, and checks caller-selected case codes. It is a new
consumer, not a CAD-1/2 requalification or copied CAD runtime.

For a deliberate failure, compile `examples/base/mismatch.astra` with
`lib/astra/hosted/equality.astra` and the hosted object. It reports code 204,
expected 1.5, actual 1.25 and both binary64 bit fields before abnormal termination.
No caller file, line, expression text, arbitrary message or stack trace is added.

## Installation and another source directory

`base/buffers.astra` installs alongside `base/slices.astra` under the configured
datadir. Their use needs neither an assertion provider nor ARGS or output support.
The generic array client qualification discovers
prefix/datadir/libdir from Meson and tests both staging and relocation outside
the compiler source directory.

Meson installs the compiler at `bin/astrac`, sources and VAPI at
`share/astra/base` and `share/astra/hosted`, and adapter source/header at
`share/astra/platform`. On the qualified Fedora configuration support objects
and `target.txt` install at `lib64/astra/x86_64-linux`. The default prefix is
`/usr/local`; Meson's normal prefix/datadir/libdir options remain authoritative.
Build artifacts are `build/lib/astra/failure-trap.o`, `failure-hosted.o` and
`target.txt`. Rebuild support for the actual target: these are not portable objects.

This fully automated, tested recipe stages an install, copies the entire prefix
and consumer sources to a fresh second location under `/tmp`, changes directory
there, and compiles/runs all examples with the relocated compiler. It also
compares post-syntax identities after relocation and removes the external copy:

```sh
python3 -B tests/baselib/integration.py build build/tests/baselib/integration
```

No working-directory lookup of library files exists. The test records every
actual absolute invocation in
`build/tests/baselib/integration/consumption-commands.json`; binaries stay in the
active build. For a persistent, manually inspectable source directory, use:

```sh
meson install -C build --no-rebuild --destdir "$PWD/build/base-install"
cp -a build/base-install/usr/local build/base-prefix
cp -a examples/base build/base-client
cd build/base-client
../base-prefix/bin/astrac contracts.astra ../base-prefix/share/astra/base/order.astra ../base-prefix/share/astra/base/classify.astra ../base-prefix/share/astra/base/contracts.astra ../base-prefix/share/astra/base/clamp.astra --link-object ../base-prefix/lib64/astra/x86_64-linux/failure-trap.o -o ../base-client-contracts
../base-client-contracts
```

No source concatenation, special directory lookup, manifest, autolinking or
package manager is involved. See [numerical contracts](numerical-contracts.md),
[failure providers](failure-providers.md), [hosted math](hosted-math.md) and the
complete validation report.
