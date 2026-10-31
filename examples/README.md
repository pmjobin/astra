# Example tour

Start with these language and library projects, using the explicit compiler from
[the root build recipe](../README.md). Source files in each project are compiled
together with the library inputs specified by their existing test/build recipes.

- `args`: arguments and views.
- `base`: functions, constants and contracts.
- `enums`: tagged values and matching.
- `generic-slices`: generic borrowed views.
- `generic-owned-arrays`: owned storage.
- `generic-copyable-values`: value copying.
- `generic-diagnostic-bags`: containers and diagnostics.
- `allocation-failure`: failure handling and cleanup.
- `application-runtime`: files, text transforms and configuration.
- `compiler-systems`: modules, native linking and counters.

For example, build and run the enum project from the repository root:

```sh
"$build/astrac" examples/enums/types.astra examples/enums/validate.astra \
  examples/enums/policy.astra examples/enums/main.astra -o "$build/enum-example"
"$build/enum-example"
```

Milestone and platform directories remain as qualification workloads. Tests and
packaging share their fixtures; their historical results do not qualify a newly
built compiler. Navigation is curated without removing unique coverage.
