# 0120: owning lazy factory and borrowed observation

Accepted for OWNED-STATE-SURGE-6-COMPLETION-1 on hosted native Astra.

`lazy property owned ExactClass value throws Error { get { ... } }` declares a
compiler-managed cache. The body is an owned producer; public property reads are
bounded receiver-borrowed observations. Exact nongeneric unique nonpolymorphic
heap Class results, including Utf8Message, are supported. The direct get-only
receiver may be caller-backed or participate in ordinary class inheritance.
Aggregate construction initializes hidden state before publishing its reference;
explicit construction does so before invoking the constructor. Nonthrowing factories
use the same ownership protocol.

The analyzer creates a distinct private factory identity from the body and a
canonical getter observation. The factory has an owned heap result and the
getter a receiver-borrowed result, even though both physical values are PTR.
Core/CFG/SSA preserve and independently verify these identities and effects;
ordinary source calls cannot select the generated factory. Weak backlinks allow
successor models to survive release of predecessors. Native v2 cache plans copy
separate factory/getter ordinals and exact retained-class destruction authority.
No C/VAPI borrowed-return or aggregate ABI is introduced.

The receiver stores Empty=0, Evaluating=1 and Ready=2 plus a pointer payload.
Cold observation enters Evaluating before invoking the factory. A checked error
unwinds factory temporaries, resets Empty and propagates the exact Error;
retry is possible. Successful ownership publishes the payload before Ready.
Warm reads borrow that identical payload without invoking the body. Recursive
observation while Evaluating traps without an unwinding guarantee. Moving a
receiver preserves its address, cache state and cleanup authority.

After the user destructor body, ready owned caches retire in reverse declaration
order before ordinary owned-field/base cleanup. Retirement disarms state and
payload before invoking the exact child destructor/free. Unused caches never
force a factory. Base and derived destructor epilogues own their declared slots.
The acyclic owned-child check includes caches.

A view may enter a direct exact borrowed consumer or null comparison. It cannot
be stored, returned, captured or promoted to ownership. Its receiver remains
borrowed throughout argument evaluation and the consuming call. Multiple stable
cache observations may coexist; moves, transfers and potentially invalidating
receiver calls during the loan remain forbidden. Ordinary replaceable field
properties retain their stricter mutation rules.

Copied lazy properties and ordinary borrowed/replacing properties keep their
existing behavior. There is no reset, async/generic/virtual owning getter,
threading guarantee, implicit RC/GC or general borrowed result. Host OOM policy
is unchanged. Historical LAZY-1 Q4 remains HELD/INCOMPLETE; this decision is a
separate qualified successor. See evidence.
