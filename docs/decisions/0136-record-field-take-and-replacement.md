# ADR 0136: record field take and replacement

Status: implemented component of unfinished Surge 10.

`var value = move record.nested.field` transfers an owned Resource, exact heap
Class or complete runtime-array field into a fresh local. The field becomes
empty. Unrelated fields remain available; another take and a whole-record move
require the relevant fields to be definitely live. Lexical cleanup accepts an
empty field and releases each remaining live field once, in the original
reverse acquisition order. Conditional and loop state use the existing
structured ownership analysis, rather than a syntax-local moved flag.

Assignment to an owned leaf first captures a complete incoming owner. A checked
producer failure leaves the old field intact. Success retires the old owner,
which may be empty after a take, then publishes the incoming owner. Replacement
restores completeness without changing the field's lexical cleanup rank. Named
incoming moves are disarmed; Resource and Class cleanup identities remain exact.

Semantic analysis diagnoses invalid source paths and ownership flow. Core and
CFG independently reconstruct root and leaf state from their own nodes. SSA
retains scalar take/replacement markers with immutable ordinal-path/rank
snapshots and exact owner events. Replacement binds its original old-field
cleanup before publication. Buffer takes and replacements instead preserve
complete PTR/I32 pairs and bind the old pair's read/deallocation. Existing native
local obligations and LLVM cleanup operand audits remain authoritative after
earlier graphs are released; no external calling convention changes here.

Validation includes O0/O1/O2 executions with independent allocation/destruction
traces and unsuppressed Valgrind. Witnesses cover checked failure before and
during replacement, repeated loop refill, conditional holes, named buffer
replacement, mixed Resource/Class/buffer fields, whole moves after refill and
returning a taken Class. Independent corruptions omit or mismatch takes,
refills, pair sources, old-field retirement and physical cleanup operands.

The source operation currently requires a synchronous nongeneric named record
local. Persistent owner-field borrows and arbitrary projection expressions
remain outside this component. Owning aggregate parameters/results, owning
tagged alternatives and the remaining G1–G9 compositions are still required.
