# Allocation-site fatal actions

Select these four sources, `application.vapi`, and the compiled application
object explicitly. With the configured installation's `bindir`, `datadir` and
`libdir` (shown here as `$prefix/bin`, `$prefix/share` and `$prefix/lib64`):

```sh
cp "$prefix/share/astra/examples/allocation-failure/"* ./
cc -std=c11 -O2 -Wall -Wextra -Werror -c application.c -o application.o
"$prefix/bin/astrac" types.astra actions.astra factory.astra main.astra --vapi application.vapi --link-object application.o --link-object "$prefix/lib64/astra/x86_64-linux/args-posix.o" -o example
./example
```

Run in a subshell with a 64 MiB address-space limit to exercise failure:

```sh
(ulimit -v 65536; ./example fatal)
(ulimit -v 65536; ./example returning)
(ulimit -v 65536; ./example default)
```

The fatal application action prints a record count and exits 2. The native
`returning_report` calls its explicitly selected C reporter, then returns; the
allocation executes its enforced trap. The default allocation traps silently.
All three are fatal. None provides fallback storage or recovery, and caller
owners are not unwound. An action may itself allocate, release consumed owners,
trap or terminate; keep reporting small where practical.

The action's receiver and arguments run only when the allocator returns null
for a positive representable request. Zero, negative counts, physical extent
overflow and bounds traps skip the action. Save an effectful count first if the
same value is needed in the action; writing the count call twice requests two
evaluations on failure. A caller's clause does not affect called-library
allocations. Explicit `T` is necessary when ordinary arguments do not infer it.

`factory.astra` is passed as a relative source label. Caller information in the
returning reporter identifies the written call in that generic definition, not
the instantiation. Opt-in file/expression bytes have the usual privacy rules.

The C object uses stdio and exit. Those are this example's dependencies; the
language requires no standard failure provider. Buffers retain direct calloc/free
and the current GNU LP64 x86-64 Linux qualification. A native action with no C
calls needs no foreign ABI. Application diagnostic units need not be bytes;
the separate CAD witness preserves its historical f64-slot diagnostic.
