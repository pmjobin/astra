# Staged scalar references in C imports

Declaration-derived C imports accept call-scoped `borrowed` pointers to i32/u32,
i64/u64 and f32/f64. `ForeignChannel(parameter="name", direction="in|out|inout")`
selects the reference direction. The default is input; its C header uses a const
pointer. This uses the same channel normalization as C exports. Existing bounded
pointer syntax and diagnostics retain their previous behavior.

The bridge checks every mandatory reference before reading or clearing caller
storage. A missing place raises the declared native error through its explicit
factory, with infrastructure domain zero and pointer status `0x80004003`. The
provider is not invoked. All input/inout values are then captured into independent
typed scratch places before any native out place is initialized to zero.

The provider receives those scratch places. Checked failure or malformed
status/error metadata leaves native inout values unchanged and out places empty.
An input reference never publishes provider writes. Successful reference outputs
publish in declaration order after status/result validation. When an out place
aliases an inout place, output initialization also empties that shared storage on
failure; input snapshots still contain the original value. Aliased successful
outputs observe the last declared publication.

Native ABI parameters retain their exact pointee independently of PTR width.
Detached mutations remove noescape, substitute a same-width u64 pointee for f64,
and change a same-typed LLVM publication value while ordinary LLVM verification
still succeeds. Restoring each mutation restores validity. Generated native
receiver parameter names also avoid collisions with actual declared parameters.

The independent C providers and Astra consumers exercise all six pointees,
bool and integer results, factories with no parameters, in/out/inout behavior,
aliases, missing places, checked rollback and invalid positive statuses. The
unique/shared O0/O1/O2 matrix includes generated-header providers and eight
whole-executable Valgrind runs. Six source negatives cover missing borrowing,
nullable places, invalid direction, unknown/duplicate channel names and owned
scalar places. Remaining import channels and M16's other gates stay active work.
