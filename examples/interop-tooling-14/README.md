# Surge 14 application witnesses

The campaign is active. All A121–A132 sources now have executing development
witnesses; complete final installed/host/profile qualification remains open.

* A121, [quota admission service](a121-quota-service.astra), exports a native
	Shared root through explicit C owners. Its [independent client](a121-client.c)
	checks admitted/denied requests, native aliases, weak expiry and exact teardown.
	Run `python3 tests/interop-tooling-14/applications.py ASTRAC EXTERNAL_OUTPUT`.
	The recipe executes GCC/Clang consumers at O0/O1/O2 and unsuppressed O0/O2
	Valgrind. Add `--prefix INSTALLED_PREFIX` for the installed compiler, provider
	and application sources; that separate final release run is still required.
* A130 is the [multi-file editor project](editor-project/README.md), executed
	through the portable LSP recipe and actual isolated VS Code extension host.
* A122 is the [binary parser](a122-binary-parser.astra). An independent C provider
	reads actual runtime files and returns typed signed/unsigned tagged packets.
	Astra verifies exact payloads, generated header constants and synchronous POD
	callback results. Its Resource owner closes on normal and all early returns.
	Run `python3 tests/interop-tooling-14/a122-binary-parser.py ASTRAC EXTERNAL_OUTPUT`;
	`--prefix INSTALLED_PREFIX` selects installed tools and sources.
* [A123–A125](windows/README.md) are the native Windows COM reconciler,
	dual-interface thermostat and C+COM lease budget. Each passed actual O0/O1/O2
	Windows execution with separately compiled SDK clients and exact lifetime
	oracles. The build recipe and serial validator preserve the distinction
	between a cross-built product and a genuinely executed application.
* [A126–A128](gobject/README.md) are live settings, a native UTF-8 diagnostic
	formatter and a dual C/GObject event publisher. All execute through real
	GObject, relocated GIR/typelib and independent C clients at O0/O1/O2.
* [A129](a129/README.md) coalesces runtime diagnostic files through independently
	installed versioned transitive packages. Its O0/O1/O2 recipe checks offline
	locks after relocation, exact Unicode/NUL output, errors, memory cleanup and
	tamper/refusal/restoration. Final release-prefix execution remains required.
* [A131](a131/README.md) executes real O0/O2 Source debugger observations of
	aggregate, closure, async, checked and independently compiled module values
	across C frames, with exact cleanup on success/exception paths.
* [A132](a132/README.md) combines actual threaded async TCP/UDP, vector PCM
	saturation, owning generic region records and a native Shared/Monitor ledger.
	Its independent clients verify exact bytes and cleanup. The recipe distinguishes
	development evidence from the required independent installed-prefix run.

Generated headers, objects, executables and receipts belong in the explicit
external output directory. Each application needs its own behavior and actual
execution; renaming a fixture does not establish another application.
