# Declaration-derived imported properties

`declarations-v1` C Class imports now accept bodyless checked properties:

```astra
[Foreign(name="amount", error_factory="foreign_fault",
         error_domain="16", errors="Fault=-1600")]
property i32 total throws Fault { get; set(i32 input); }
```

`owner.total` calls `prefix_get_amount`; `owner.total = value` calls
`prefix_set_amount`. A read-only declaration contains only `get;`. Accessors have
no provider implementation bodies. The setter has one explicit typed parameter.
Each accessor carries its own normalized member kind and shares the property's
source ordinal. Generated internal native names avoid collisions with declared
methods. Foreign names retain the normal API-wide uniqueness rules.

Getters and setters use the existing typed import adapters, status/error checks,
private results, record forwarding and ownership retirement. Native catches and
`throws` checking apply to both accessor forms. A setter can borrow or explicitly
consume an imported handle; a consuming assignment requires `move`. A getter can
return an owned independent byte/text snapshot or exact nominal object owner.
Copied POD getters work in initialization, return, argument and field projection
contexts. A property does not grant a storable borrow of provider-owned storage.

The accessor types must describe the same logical foreign value. Their native
transport can differ where the existing channel model requires it. For example,
an owned UTF-8 getter uses `owned u8[]`, while its setter takes a native `string`:

```astra
[Foreign(error_factory="foreign_fault", error_domain="16", errors="Fault=-1600")]
[ForeignChannel(parameter="result", encoding="utf8-counted")]
property owned u8[] title throws Fault { get; set(string input); }
```

The getter validates UTF-8, copies into an independent native byte owner and
retires the matching provider allocation. The setter passes the native string's
exact byte count; counted text preserves embedded NUL. The byte owner can feed an
ordinary native UTF-8 factory. It never receives a static or receiver string
lifetime. An unannotated byte snapshot is logically bytes and cannot be paired
with a text setter merely because both carriers contain addresses and counts.

`ForeignChannel(parameter="result", ...)` selects the getter result. Other channel
annotations select the explicit setter parameter. Duplicate or unknown selectors
reject. Owned handle setters and nullable getter results keep their separate
transfer facts while requiring the same nominal value type. An explicit
`null_status` applies to the getter; the void setter requires ordinary success.

The property integration recipe uses independently authored and generated-header
C providers, unique/shared roots, O0/O1/O2 native objects and O0/O2 record
forwarders. It exercises all seven copied scalar kinds, mixed POD and closed
generic records, counted bytes, UTF-8 with embedded NUL, owned child handles,
failed setters and dirty/malformed getter results. Detached mutations substitute
same-signature property accessors in Core, CFG, SSA, native planning, C ABI and
ordinary-valid LLVM. Memory checks cover actual native/C execution and compiler
mutation proofs. The source-bound qualification ledger records completed runs;
this feature remains an intermediate part of M16, whose G0–G9 are still required.
