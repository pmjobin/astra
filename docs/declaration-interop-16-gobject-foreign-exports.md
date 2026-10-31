# M16 GObject exports of foreign GObjects

Declared native Shared methods can accept borrowed/full imported GObjects and
return owned/nullable imported GObjects. Their public SDK types come from the
exact immutable import contract and its SDK header. Conversion adopts an actual
foreign reference into a scoped native carrier; it never treats foreign payload
storage as a native Class. Borrowed inputs acquire a temporary reference. Full
inputs take responsibility before validation so every failure path retires the
incoming reference. Successful full results extract the provider reference and
retire the native carrier without an extra reference or payload copy.

The independent C provider consumes the generated public header and exercises a
new native Shared facade. Its native methods perform borrowed reads, construction
and ownership relay. The C client observes exact pointer identity, nullable full
results, native arithmetic, full input cleanup on missing result, wrong GType and
disposed receiver failures, and exact provider finalizer counts. The existing
unique C Consumer remains unique. Five native/adapter optimization combinations
and two Valgrind clients pass. This is intermediate M16 evidence; remaining GIR,
record import, signal, composition, personality and final qualification gates are
still required.
