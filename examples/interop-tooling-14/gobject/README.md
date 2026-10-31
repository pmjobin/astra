# GObject applications A126–A128

These distinct Astra programs execute through real independent GCC/Clang
clients and scanner-generated GIR/compiled typelibs at O0/O1/O2. The portable
`tests/interop-tooling-14/gobject-applications.py ASTRAC EXTERNAL_OUTPUT` recipe
moves each complete library/header/GIR/typelib/client installation before use.
Add `--prefix INSTALLED_PREFIX` for installed compiler, providers and sources.

* A126 is a live configuration bitset. Native code records the number of
	individual bits changed. The C client observes three committed property
	signals and five bit revisions, unchanged/refused inputs, stable GObject view,
	wrong-thread refusal, restored data access, weak notification and one native
	destruction. A separate relocated GI client checks the same real GType.
* A127 formats diagnostics using native owned `Utf8Message`/`ReportText`, checked
	exceptions and severity properties. Its explicit SDK companion copies scalar
	bytes into an annotated transfer-full GLib UTF-8 string. The native owners
	retire before returning; no native layout or exception crosses the boundary.
	The real scanner identifies the report method, full transfer and error channel.
	Independent C and relocated Python GI clients check Unicode, independent
	retained strings, native rejection mapped to GError, property signals, disposed
	errors and exact cleanup. This is a bounded copied adapter, rather than a new
	compiler text-property ABI or direct foreign access to native Text storage.
* A128 is an event publisher accumulating an ordered checksum. Separate C and
	GObject views mutate one root. Externally retained listener contexts remain
	alive until disconnect/disposal; disposal inside delivery quiesces later
	handlers. The C owner then continues using the same native root, recreates its
	GObject view and retires all owners. The oracle requires checksum 637281 after
	five events, two foreign-view weak notifications and one native destruction.

The selected GNU C11 SDK dialect accommodates installed GLib's public GNU
macros; warnings remain errors. O0/O2 independent clients run unsuppressed
Valgrind with definite, indirect and possible leaks treated as errors. GLib's
reachable process caches are distinct from native payload/owner retirement.
The recipe records all input/product hashes and actual process output. These
development runs do not replace final frozen-source release qualification.
