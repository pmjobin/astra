# Concrete enum values

This application validates a small header and handles every HeaderResult,
LoadError, and DecodeError variant in Astra. HeaderResult carries an independent
Header record or a nested error value. These are ordinary copyable values.

From this directory, with the built or installed compiler on PATH:

```sh
astrac types.astra validate.astra policy.astra main.astra -o header-example
./header-example
```

The four sources may appear in any order. Successful execution exits with zero
and produces no output. This example needs no provider or allocator. For a
concrete generic-record composition control, see `tests/enum-1/source.py`.

The [language guide](../../docs/language/enums.md) describes construction,
snapshots, exact nominal types, named patterns, and the next ENUM-OWN-1 boundary.
