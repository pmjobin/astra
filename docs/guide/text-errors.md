# Text, failures and useful diagnostics

A useful program must explain results and handle expected failures. Keep text
ownership and formatting cost visible instead of treating every interpolation
as a freely escaping string. This program writes into a reserved builder, then
separately materializes an owned message:

```astra example=formatting
language astra27b;
int main() {
	try {
		var builder = new Utf8ByteBuilder();
		if (!builder.reserve(64)) return 1;
		int value = 42;
		if (!format_into(builder, $"reading {value}")) return 2;
		var snapshot = builder.snapshot();
		if (snapshot.text != "reading 42") return 3;
		var message = format_text($"value {value}");
		if (message.text != "value 42") return 4;
		return 42;
	} catch (Error error) {
		return 5;
	}
}
```

The first operation writes `reading 42` through the borrowed builder. The
snapshot's exact text is checked. `format_text` then produces the owned message
`value 42`; it has a different lifetime/cost contract. Both use an immediate
typed interpolation plan. The selected libraries in the example manifest supply
the real builder, scalar formatting, message and error definitions. Their
authenticated C providers are explicit link inputs.

An adequately reserved sink can avoid another allocation during a measured
formatting interval. Creating/reserving the builder can allocate. Do not shorten
that distinction to “formatting never allocates.” UTF-8 byte length also differs
from character or grapheme count, and escaped NUL is part of counted text.
See [Text](../reference/text.md).

## Recover from a rejected value

Validation can fail without terminating the whole process:

```astra example=errors
language astra27b;
int positive(int value) throws Error {
	if (value < 0) {
		throw new Error("negative reading");
	}
	return value;
}

int main() {
	try {
		int rejected = positive(-1);
		return rejected;
	} catch (Error error) {
		if (error.message == "negative reading") return 42;
		return 1;
	}
}
```

The validator declares its error bound. Its negative path creates a real error;
the handler checks its exact message and returns the expected 42. The selected
exception-root source and hosted text provider are part of the build, not an
implicit global runtime. Scope cleanup still applies on the admitted error path.
Fatal allocation actions and bounds traps do not promise the same unwinding.

## Read the stage of a diagnostic

The next whole program is deliberately invalid:

```astra example=negative-type
language astra27b;
int main() {
	bool value = 42;
	return value;
}
```

It fails type checking before native code. A malformed token can fail even
earlier; a source with admitted syntax/types can fail independent Flow/Core/SSA
verification later. Preserve the exact source and diagnostic stage when reporting
an issue. The current driver reports UTF-8 byte offsets, so do not treat them as
screen columns. Do not “repair” a failing example by disabling a verifier or
changing an ownership promise. [Errors](../reference/errors.md) and
[Tooling](tooling.md) provide the precise effect and evidence workflow.
