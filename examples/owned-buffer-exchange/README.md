# Exchange two record-buffer owners

`ExchangeOwner.rotate()` contains the complete application operation:

```astra
swap(this.state, this.next);
```

The example starts with two and three Kernel records. It compares both rotations
with an independent element-copy control, changes a record after the first
rotation, and checks that a saved record remains independent. Normal return cleans
the final contents of both objects. The copy control allocates to reproduce the
differing lengths; the exchange itself allocates nothing.

The development compiler and a relocated installation each passed all 24 orders
with identical executable bytes and source-aware diagnostics. The campaign report
records the final strict builds and installed qualification.
From this example directory, after building the compiler and selected providers:

```sh
../../build/own-swap-1/development-build/astrac \
	types.astra values.astra owners.astra main.astra \
	../../lib/astra/base/buffers.astra ../../lib/astra/base/slices.astra \
	../../lib/astra/base/diagnostics.astra \
	--link-object ../../build/own-swap-1/development-build/lib/astra/args-posix.o \
	--link-object ../../build/own-swap-1/development-build/lib/astra/diagnostics-hosted.o \
	-o ../../build/own-swap-1/owner-example
../../build/own-swap-1/owner-example
```

Explicitly selected source libraries are `base/buffers.astra`,
`base/slices.astra` and `base/diagnostics.astra`; providers are exactly
`args-posix.o` and `diagnostics-hosted.o`. Passing an extra argument deliberately
fails the assertion on the consumer of the exchanged `next` field, retaining
the relative source label and expression. No library intrinsic named swap exists.
