# ADR 0164: bounded Actor mailboxes

Accepted explicitly by the user during the native Surge 13 session.

An Actor owns a bounded FIFO mailbox and one named, dedicated hosted
executor. Multiple producer threads use explicitly cloned sender handles.
Messages carry copied scalars or owned native Classes; borrowed and
thread-bound messages are forbidden.

A send attempt consumes its owned message. Admission to a full or closed
mailbox reports a checked error and destroys the rejected message exactly
once. One synchronous, nonthrowing handler runs at a time. Handlers may
catch checked native errors internally.

Cancellation destroys queued messages before execution. Active work finishes
or cooperatively cancels before shutdown joins the executor and destroys
the receiver. Handlers cannot suspend or synchronously wait on themselves.
Actor/Monitor composition is rejected.

Shared sender handles have explicit local costs. The receiver remains
uniquely owned unless separately qualified sharing is selected. Ordinary
Classes retain their existing unique lifetime. This profile does not claim
general actors, distributed delivery, supervision, cycle collection, or an
implicit global executor.
