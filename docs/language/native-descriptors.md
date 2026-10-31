# Selected native descriptors

Generate metadata only for declarations the application intends to inspect:

```sh
astrac --emit-native-descriptors --descriptor-module Witness \
  --describe MetaReading --describe Point=Models.Point \
  lib/astra/base/errors.astra model.astra -o metadata.astra
astrac -O2 lib/astra/base/errors.astra model.astra metadata.astra client.astra -o client
```

The first command checks the original program through LLVM before writing the
generated source. Compile that source with the same model declarations and
normal application inputs. Generation supports hosted host compilation and
requires the explicitly selected standard Error root. Keep generated outputs
in the build directory and keep their generation recipe with application source.

```astra
using NativeMetadata_Witness;

int inspect(MetaReading receiver) throws Error {
	var type = lookup("MetaReading");
	var selected = member(type, 0);
	string name = member_name(selected);
	string kind = member_kind(selected);
	string contract = member_type(selected);
	return read_MetaReading_int(receiver, selected);
}
```

`lookup`, `from_id`, `type_name`, `type_kind` and `type_member_count` describe the
selected nominal declarations. `member` takes a checked zero-based ordinal;
`member_name`, `member_kind` and `member_type` report the declared member and its
type/ownership contract. All queries throw Error on invalid module/version,
unknown ID or invalid ordinal. An interface descriptor describes its contract;
it does not discover the dynamic Class of a receiver.

For each selection, `read_Alias_int` reads supported int fields/properties and
`call_Alias_int(receiver, member, argument)` invokes supported int methods with
zero or one int parameter. A zero-parameter method ignores `argument`. Other
members remain descriptive and these helpers throw if asked to operate on
them. Reference receivers are nullable and checked before use. Receiver types
are statically checked; an unrelated Class cannot be supplied through a
descriptor. A record reader is generated only for a recursively copyable
record. No helper returns an owned field, mutable backing or raw storage.

Version 1 supports 1..32 nongeneric native Classes, records and interfaces, each
with at most 256 public declared members. Private fields, lifecycle functions
and synthetic lazy factories are omitted. Member order follows source order;
inherited members are selected through their own declaration. Module and alias
identifiers have at most 64 ASCII characters. `Alias=Qualified.Type` avoids
ambiguous helper names. The generated `NativeMetadata_MODULE` namespace must
be unused by the inputs.

Descriptors use copied integer records and collision-checked nominal hashes.
They are inspection data, with no authority to reinterpret storage or transfer
ownership. They are not authenticated tokens or persistent cross-version
schemas. Regenerate after changing declarations, including member order.
Compiling without the generated source adds no registry or per-object metadata.
There is no implicit dependency on GObject, regex, io_uring or a JIT.

The [decision](../decisions/0151-opt-in-native-declaration-descriptors.md) records
the finite profile and its independent controls.
