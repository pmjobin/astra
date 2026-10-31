# A29 — owning message transformation

`owning-message-transform.astra COUNT EARLY` accepts 0–100 records and an early
return switch 0/1. A factory returns `Closure<MessageTransform,int,int>`;
forwarding moves its single ownership. The environment owns a unique generated
message prefix, an explicitly cloned shared pricing snapshot and a cloned weak
observer. Each invocation upgrades the observer, builds owned UTF-8 from the
record number and calculated amount, and emits `item=N amount=3*N`.

For `3 0`, message output is `item=1 amount=3`, `item=2 amount=6`,
`item=3 amount=9`. For `6 1`, the consumer returns after two records and totals
9. `0 0` emits no message. The C observer independently emits constructor and
reverse destructor events; `event=7:TOTAL` follows closure destruction and a
failed weak upgrade. Normal runs exit 0; malformed arguments exit 64; checked
input/output setup failure exits 2. The indirect code is nonthrowing and catches
its owned UTF-8 snapshot errors internally.

# A30 — checked closure rollback

`checked-closure-rollback.astra MODE` accepts 0, 1 or 2. Mode 0 throws before
capture; mode 1 throws after unique/shared/weak capture and a successful upgrade;
mode 2 invokes the closure, observes 42, then throws. Catch prints respectively
`before capture`, `after capture and upgrade`, or `after invocation`.

The C event trace proves captured journal and closure environment destruction
before catch, the original shared state still reads 30 after catch, and its
single destructor runs on explicit terminal release. A later weak upgrade fails
and output ends with `expired`. Normal runs exit 0; malformed arguments exit 64;
checked input failure exits 2. Checked effects are on the owning caller; binding
a code function that itself throws is refused by the finite closure signature.

`tests/language-runtime-4/closure-check.py` independently calculates expected
bytes, builds both apps through public O0/O1/O2, runs empty/early/failure cases,
and checks unsuppressed Valgrind results. It also tests distinct i32/i64 closure
signatures, ownership negatives and separately compiled GCC/Clang C clients.
Generated products and complete command receipts belong in its explicit
external output directory.
