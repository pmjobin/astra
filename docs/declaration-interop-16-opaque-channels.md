# Opaque foreign channel composition

M16 remains active. This integration extends the existing compiler-pinned `/4`
native-unit profile with declaration-only C and GObject imported Classes alongside
the already supported COM interfaces. Each foreign nominal declaration retains a
separate source origin, bodyless members and its exact checked contract identity,
including factory, target selection and cleanup. Imported declarations never become
native Classes or implementations. The native-unit dependency graph carries their
contracts; consumer compilation reconstructs and independently checks them.

Owned foreign object properties and nonvirtual copied checked properties now retain
their explicit result ownership and throws bound in native declaration prototypes.
Lazy property caches remain outside this profile. Scalar references require an
exact borrowed typed scalar pointee; the native signature identity records that
pointee separately from pointer width. This adds no unrestricted pointer channel.

The export witness compiles the existing broad GObject implementation into an
opaque leaf, a separate native inspector component, then an adapter and consumer.
It executes owned object and counted text properties, a copied checked property,
scalar references and a closed `Pair<f64>` across that graph. Independently authored
C and GI clients also exercise the broad exported methods and five property types.
All eight O0/O2 leaf/component/adapter combinations and one O1 combination execute.
Source copies are removed before dependent compilation, and an `openat` trace
checks actual interface/object access. Re-sealed declaration mutants change owned
property, checked-effect and pointee facts and reject before executable emission.

The import witness reconstructs both a unique C provider and an actual GObject
provider from an opaque native interface. Native code in the library and a separate
consumer call the imported members. Independent C/GLib implementations supply the
providers, checked errors and destruction observers. O0/O1/O2 execute; source-hidden
access traces and re-sealed nominal contract mutations check declaration authority.

Both recipes put products outside the checkout:

```sh
python3 tests/declaration-interop-16/opaque-channels.py /absolute/astrac /absolute/output
python3 tests/declaration-interop-16/opaque-imports.py /absolute/astrac /absolute/output
```

The accompanying ledger records exact compiler/source identities, executed-client
memory checks and four complete compiler executions under unsuppressed Valgrind.
It also retains the invalid first test fixture and incorrect mutation resealing
attempt, both corrected without weakening compiler checks. These are composition
prerequisites; API A, the frozen API B challenge and final G0–G9 remain pending.
