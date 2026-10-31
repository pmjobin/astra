# Owned buffer exchange

Implemented and qualified; see [ADR 0084](../decisions/0084-owned-buffer-exchange.md)
and the validation report.

```astra
swap(left_owner_place, right_owner_place);
```

`swap` is a reserved native keyword with exactly two expression operands and a
required semicolon. It is a statement with no value. It cannot appear in an
initializer, condition, return value, constant expression or allocation-failure
call. Normal expression parsing applies, followed by owner-slot checking.

| Operand | Eligibility |
| --- | --- |
| Initialized live owned buffer local | Yes |
| Live consuming buffer parameter | Yes, through its acquired owner slot |
| Initialized owned native class field | Yes, through an existing admitted receiver |
| Borrowed slice, fixed array, indexed element or record subfield | No |
| Property, value, allocation or call result | No |
| Move expression, pointer indirection, constant or non-owning slot | No |
| Possibly moved, released or uninitialized owner | No |
| Direct Resource/Class owner, generic class or owned struct field | No |

Any combination of admitted local, parameter and field slots is permitted when
their canonical buffer types and cleanup contracts are identical. `int` and `i32`
are aliases; distinct nominal records are distinct types even when layouts match.
Existing scalar/vector/mask and trivial record element eligibility is unchanged.
Text and ownership-bearing elements remain excluded.

The statement exchanges complete owners: allocation base and element count.
It does not exchange elements, copy payload bytes or allocate/free memory.
Counts may differ, and either or both owners may be empty. A live zero-length
owner is not a moved or released slot. The statement cannot initialize or rearm a
dead slot. Ordinary explicit-move rules remain in force elsewhere.

The left receiver and destination checks occur first, once. The right follows,
once. A left trap prevents right evaluation; a right trap leaves both slots
unchanged by the exchange. Earlier explicit effects are not rolled back. Storage
captured on the left must remain valid during evaluation on the right.

After both destinations are valid, both complete descriptors are captured before
any descriptor store. No user call, conversion, cleanup or fallible check occurs
between these captures and completion. Fields have no observable uninitialized
state. This is not an atomic operation for threads or signals.

Self-swap and aliasing borrowed receivers selecting the same physical field are
valid. Both evaluations and checks still happen. The operation assumes legitimate
unique owners; it does not validate hostile or forged foreign allocation aliases.

No dependent slice, element address or pending indexed destination/receiver may
retain an owner proof across either side of the exchange. Existing conservative
containing-object overlap restrictions apply. A complete saved record is an
independent value and may survive. Borrowed access to a class itself does not
prohibit mutating its already initialized owned fields.

Slots keep their declared cleanup rank, scope and field responsibility. Each
eventually cleans the allocation it received. Local/field exchange can change
which allocation dies at local scope exit. User deinit can exchange initialized
fields before automatic reverse field cleanup. Constructors can exchange only
after the ordinary initialization and receiver-use checks are satisfied.

Generic `owned T[]` locals and parameters use the existing GEN-BUFFER premises;
the statement creates no constraint. Two symbolic operands need the same lexical
element identity. A consuming helper can exchange incoming owners, return one and
clean the other, but ordinary call/move semantics still apply: it is not a general
function that mutates caller slots by reference.

Only exact lowercase native `swap` is reserved. Other case spellings, foreign
cname strings and VAPI metadata retain their existing policy. The independent
library element-value algorithm `swap_elements` is unchanged.
