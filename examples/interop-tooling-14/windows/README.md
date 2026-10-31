# Native Windows applications A123–A125

These are three distinct Astra programs using the approved registration-free
x86-64 Windows COM profile. All ran at O0/O1/O2 in the existing Windows 11 VM.

* A123 reconciles six account updates through an independently compiled SDK
	provider DLL. The independent client checks checksum 810765, final value 6,
	32 repeated transactions, both IIDs, clone/move cleanup, null/failed QI and
	data results, allocation failure at acquisition/clone, a real MTA worker's
	wrong-thread refusal, missing apartment and restored STA use. Every acquired
	wrapper retires and the provider is destroyed once before DLL unload.
* A124 exports a thermostat with clamped 10–30 settings and an adjustment count.
	The independent SDK client uses only the COM factory/interfaces. It checks
	the canonical IUnknown, distinct application views, exact AddRef/Release
	counts, null/missing-IID errors, actual property behavior, S_FALSE/failed
	scaling, wrong-thread calls/QI, missing/changed apartment and restored calls.
	The last view destroys the native payload once, at temperature 10 after
	exactly three adjustments.
* A125 exports a consumable lease budget through separate C and COM views of
	one root. Requests through either view spend from the same capacity; invalid
	expenses leave it unchanged. The client checks stable live wrapper identity,
	C/COM/native pointer separation, exact counts, wrong-thread data/adaptation,
	weak upgrade while only COM owners remain, final expiry and exactly one
	destruction after all 60 units have been spent.

`tests/interop-tooling-14/windows-applications.py --help` describes the explicit
compiler/MinGW/sysroot/output recipe. The SDK clients compile independently of
generated headers. The importer reuses the independent component-test provider;
its reconciliation algorithm and oracle are new. The build receipt alone says
BUILD_ONLY. `com-host/capture.py --profile applications` additionally requires
all nine guest process exits, all product hashes and all application markers.

The optional ISO contains only test products. `run.cmd` copies them to a fresh
`%TEMP%\Astra14Apps-*` directory and calls explicit in-process factories. It
does not register classes or install anything. Native execution requires an
authorized Windows host and is separate from building the ISO.
