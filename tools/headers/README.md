# Explicit evaluated C header constants

`import.py` evaluates explicitly selected C `int` macro/enum constants using the
chosen installed host C compiler. It emits ordinary typed `CImport` getters and
native `const int` declarations; it adds no new Source or native ABI semantics.
The selected target is GNU x86-64 Linux LP64. No compiler or SDK is installed or
selected implicitly. The tool compiles and executes a small probe including the
selected trusted headers, so run it only for headers you intend to compile.

An example profile is:

```json
{"format":"astra-c-header-profile/1","target":"x86_64-linux-gnu-lp64","headers":["packet.h"],"constants":[{"macro":"PACKET_MAGIC","name":"magic"}]}
```

Include names are relative to the profile directory or normal compiler system
search. Selection admits identifiers, rather than executable C expressions in
the JSON. The C compiler evaluates expressions contained in the actual headers.
Each selected expression must be an integer constant expression of exact C `int`
type in signed 32-bit range. Unsupported types, runtime expressions and missing
symbols fail before output publication. Date/time macros reject under compiler
diagnostics. Probe/profile path macros use canonical prefix maps and
`SOURCE_DATE_EPOCH=0`; no wall-clock input is accepted silently.

```sh
python3 tools/headers/import.py --profile /external/sdk/profile.json \
	--cc gcc --work /external/build/header-scratch --output /external/build/header-bindings
python3 tools/headers/import.py --profile /external/sdk/profile.json \
	--cc gcc --work /external/build/header-scratch --verify /external/build/header-bindings
```

Run `--verify` before compiling generated products. The contract binds profile,
generator, compiler/version/target, complete preprocessed translation unit,
evaluated values and product hashes. Generation in independent directories is
byte-identical for the same inputs. Transitive header changes affect the
preprocessed hash even when selected values happen to remain equal. These hashes
establish consistency, rather than SDK authenticity or package signing.

Compile `bindings.c` independently with the profile's header include directory;
pass `bindings.astra` as a normal Source input and link the C object explicitly.
`Header_magic` is a frozen native constant and `header_magic()` is its C getter.
Generated C checks the current header value against the recorded value and
returns that frozen value. Stale header compilation rejects; getters include the
full contract hash in their symbol, so a stale bridge cannot satisfy regenerated
Source declarations. No automatic include, library, package or linker action is
performed by `astrac`.

The portable `tests/interop-tooling-14/c-headers.py ASTRAC EXTERNAL_OUTPUT` recipe
executes GCC/Clang bridges and Source consumers at O0/O1/O2, including the minimum
signed integer, enum and derived macro expressions. It checks independent output
reproduction, every product's tamper/restoration, transitive header changes,
stale compile/link rejection, unsupported types and malformed profiles, plus
unsuppressed Valgrind. Arbitrary C expressions, function-like macro expansion
arguments, unsigned/floating/string constants and cross-target probe execution
remain outside this selected tool profile.
