# M16 opaque shared GObject SDK

The existing `/4` implementation generates a shared GObject SDK from an opaque
native unit without further compiler changes. The new fixture defines a shared
Class with a mutable property, checked floating-point method, owned byte snapshot
and typed callback. Its implementation source copy is removed before generating
the SDK from the pinned interface and existing object.

Five native/bridge optimization combinations execute an independent C client,
scanner-produced GIR/typelib through PyGObject, and a fresh Astra consumer generated
by the strict GIR importer. The C and GObject views observe the same native state
and retire the native owner exactly once. The Astra consumer uses a captured
Closure for the call-scoped callback and catches the declared checked error.
Two C clients and two Astra consumers pass unsuppressed memory checks.

The recipe creates the SDK prefixes outside the checkout and records generated
headers, library, GIR, typelib, imported declarations, consumers and exact hashes.
The companion JSON combines the unchanged compiler's previous 114 green
registrations with this new registered test. The added test registration does not
change compiler source or its executable hash.

This remains an intermediate prerequisite. Opaque COM contracts and Windows units,
retained signals, the frozen compiler challenge and final complete G0–G9
qualification remain unfinished.
