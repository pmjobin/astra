# 0083: Resume idiomatic CAD application qualification

Status: accepted application qualification policy for APP-CAD-2.
The numbered registry through 0082 was checked before assigning 0083.

Resume the selected CAD application at
`f415381f92daecfa683838206dffa5ea78d78477`, with compiler implementation,
pre-existing libraries/providers, language semantics and normal driver flags
frozen at `0e847be42a00be7f8d85c4c50f813a8d0c540cb3`. This decision introduces
no compiler or language change and no new downscaling algorithm.

APP-CAD-1 remains historically BLOCKED_COMPILER for I, with qualified L/P.
ALLOC-FAIL-1 closes the allocation-failure boundary; its full I outcome remains
NOT_RUN/INCOMPLETE. Only a new complete qualification can establish full I PASS.

Keep separate source and execution identities for historical L, compatibility P
and native-state I. Reuse retained receipts only after verifying their actual
inputs, executables, dependencies and observations. Rebuilt nonidentical programs
need their applicable acceptance. Native parity is exact; independent Python
oracle tolerances and original expected results are unchanged.

All thirteen logical numeric buffers, including output, must have native owners.
Application-only PNG, argument, scalar math and observation boundaries may remain.
Preserve allocation order and fatal diagnostics in their historical logical units.
Normal returns must release owned state; original fatal exits do not unwind.

Use mandatory local input preflight, exact source recipes, intermediate source
freezes and a final acceptance freeze. New evidence and scratch belong under
`build/app-cad-2/`; earlier evidence, protected work and private assets remain
unchanged. Timing follows correctness and a declared matched P/I plan.

A missing exact input is BLOCKED_INPUT. A required frozen-compiler limitation
needs a minimized witness and exact compiler evidence before BLOCKED_COMPILER.
An unresolved native/oracle/protocol mismatch is FAIL_CORRECTNESS. On a genuine
blocker, stop the affected implementation and deliver its honest report and
reproducer in the single campaign commit. No compiler repair is authorized.
