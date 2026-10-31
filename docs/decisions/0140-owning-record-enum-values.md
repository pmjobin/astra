# ADR 0140: complete owning records in enum payloads

Status: implemented component of unfinished Surge 10.

An enum field whose concrete record type owns fields derives ownership without
an additional source annotation. Every stage checks this against its own record
field graph. A copyable record keeps its existing copied payload semantics.
An owning record field accepts an explicit whole move of a named record. A
containing enum is move-only, including empty alternatives and nested enums.

Record payload evaluation uses the same complete value capture as native record
arguments. A successful constructor commits the source only after all payloads
are evaluated. A checked later-argument failure leaves the source live for its
normal cleanup. Source and Core reserve the entire record, including its exact
owning leaf paths. CFG/SSA retain the complete original record move and its one
constructor field consumer. Buffer fields remain inseparable pointer/count
pairs through capture and committed source disarming.

A consuming match publishes a grouped record result, consumes it completely and
acquires a fresh record root using the existing record boundary machinery.
Resource, heap Class and buffer fields acquire their original cleanup contracts.
The retained-case mask transfers the whole selected field; ignored record
fields are destroyed as part of the active case. Extracted records support the
existing bounded field take/refill, whole-value transport and return rules.
Class fields retain heap origin through a record binding and later extraction.

The enum's native record storage reuses `NativeStructValuePlan`, with exact
nominal declaration, physical value channels and original cleanup inventory.
It stores a flat tuple of those channels inside the selected alternative. This
is distinct from `NativeRecordElement`, whose array/POD layouts retain their
trivial destruction requirements. Native source correspondence reconstructs
the record shape; detached verification requires the exact program-owned value
plan, complete pairs and declaration cleanup. No raw pointer grants ownership.

LLVM stores and reads the exact tuple fields and publishes the enum tag after
the payload is complete. Destruction follows the selected alternative in reverse
field order and each record's declared field order in reverse. A moved value is
a fresh lifetime, consistent with record parameter/result transport; local
construction failure retains its written acquisition order. Scalar cleanup uses
the original Resource destructor or concrete heap Class destructor and free.
Buffer cleanup retains the complete static element plan. Physical projection,
operand and operation-order audits survive upstream graph disposal.

The witness combines checked argument failure, record return forwarding,
nested enums, Class extraction, buffer take, field refill, destructive case
replacement and two record payloads beside a scalar Resource. Corruption controls
cover copied Core producers, missing CFG/SSA commits and bindings, erased pair
disarms/acquisitions, native cleanup/pair corruption and LLVM-valid tuple field
substitution. The public trace is authored independently of execution and is
checked at O0/O1/O2 under unsuppressed Valgrind.

An extra corruption probe exposed a shared disposition gap: replacing an arm's
retained-field finish with a full active-case drop could pass verification after
a binding had acquired that field. CFG and SSA now require the converse of the
existing mask check: every consuming binding must have its exact later retained
disposition. This applies to Resource, Class, buffer, nested enum and record
bindings. Full disposal in place of transfer is rejected, and restoration is
checked independently at both stages.

This follows the existing concrete synchronous record boundary profile.
Named record inspection loans and fresh owning record factory arguments remain
outside this profile. Generic owning containers, wider properties/borrows,
separate native units and the integrated application corpus remain campaign
work. Default nullability, unique ownership and external C/GObject ABI are
unchanged.
