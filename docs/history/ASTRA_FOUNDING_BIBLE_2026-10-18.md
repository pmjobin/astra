ASTRA — FOUNDING BIBLE
Canonical handoff for the new compiler/language project
Snapshot: September 2026


======================================================================
0. PURPOSE OF THIS DOCUMENT
======================================================================

This document establishes the founding architectural continuity for Astra.

Astra is a new programming language and compiler project descended conceptually
from Vala and from the lessons learned while developing the experimental Vala
LLVM-v2 backend.

Astra is NOT:

    llvm-v3 inside Vala
    a new Vala backend
    a fork that must remain upstream-compatible
    a GObject-native language
    a compatibility wrapper around valac

Astra IS:

    a new language
    a new compiler
    a new repository
    a new architectural lineage

Vala and the frozen LLVM-v2 backend are ancestors, compatibility references,
semantic oracles, and sources of proven compiler-design lessons.

They do not have architectural authority over Astra.


======================================================================
1. PROJECT IDENTITY
======================================================================

Working/founding name:

    Astra

The name was chosen because:

    - it has a compact cadence reminiscent of Vala;
    - it is clearly distinct from Vala;
    - it has a deliberate personal connection to Asteria;
    - it feels appropriate for a systems language intended to power unusual,
      ambitious, and occasionally cursed inventions.

Before any broad public launch, perform a proper project/name/trademark
collision review.

Until then, Astra is the canonical working project name.


======================================================================
2. WHY ASTRA EXISTS
======================================================================

The Vala LLVM-v2 effort succeeded.

It proved that direct LLVM lowering of substantial Vala semantics is practical
and helped establish reliable abstractions for:

    ownership
    storage identity
    CFG/SSA lowering
    calls and ABI
    generic erased ownership
    provider authority
    delegates/callables
    ref/out semantics
    generated-C compatibility fallback
    strict fail-closed native selection

However, V2 also exposed a deeper architectural limit.

A compiler whose native semantics continue to inherit generated-C and GObject
implementation decisions will permanently lose optimization freedom and will
continue to carry historical constraints that are unnecessary for a new
language.

The project therefore deliberately stops trying to evolve Vala indefinitely.

Astra begins cleanly so that we may:

    choose our own license
    avoid upstream governance/turf constraints
    remove historical compatibility cruft
    make compatibility-breaking language improvements
    implement first-class lazy properties
    implement modern async
    design a native object model
    design for embedded/freestanding systems
    expose SIMD/DSP semantics directly to LLVM
    control native ABI and runtime policy
    retain excellent C interoperability without inheriting GObject internally


======================================================================
3. FOUNDING DOCTRINE
======================================================================

The central architectural principle is:

    NATIVE FIRST, COMPATIBILITY AT THE BOUNDARY.

Language semantics belong to Astra.

Foreign object systems and ABIs are compatibility boundaries.

In particular:

    Astra semantics are not defined in terms of generated C.

    Astra semantics are not defined in terms of GObject.

    Astra native objects are not GObjects internally.

    Astra runtime type identity is not synonymous with GType.

    Astra properties are not inherently C getter/setter calls.

    Astra async is not GLib begin/end callback ABI.

Conversely:

    C interoperability is permanent and first-class.

    GObject interoperability is important.

    VAPI-style typed foreign declarations are important.

    GIR integration is desirable.

The distinction is:

    compatibility is preserved at explicit boundaries,
    rather than forcing the native language model to be foreign-compatible
    everywhere.


======================================================================
4. ARCHITECTURAL NORTH STAR
======================================================================

The intended high-level compiler pipeline is approximately:

    Astra source
        ↓
    parser
        ↓
    checked semantic model
        ↓
    semantic Core IR
        ↓
    ownership + CFG normalization
        ↓
    native object/property/call semantics
        ↓
    physical lowering
        ├── Astra native ABI
        ├── C / VAPI foreign ABI
        └── GObject adapter ABI
        ↓
    LLVM IR
        ↓
    target code

Critical rule:

    optimizer-visible semantics must not be lowered into opaque foreign calls
    earlier than necessary.

Examples:

    PropertyRead
    PropertyWrite
    ObjectCreate
    VirtualCall
    InterfaceCall
    TypeCheck
    LazyPropertyRead

should survive semantically long enough for Astra to optimize them.


======================================================================
5. RELATIONSHIP TO VALA
======================================================================

Astra is Vala-descended.

Astra is not required to be Vala source-compatible.

The language should initially retain the aspects of Vala that have extremely
high value:

    concise C-adjacent syntax
    explicit ownership concepts
    properties
    delegates
    classes/interfaces/value types
    strong C interoperability
    VAPI-style API descriptions
    low ceremony for native code

However, Vala behavior is not binding when a compatibility break produces a
materially better language.

Examples of intentional freedom include:

    new lazy-property semantics
    new async model
    native object ABI
    improved generics
    different runtime type machinery
    stronger embedded guarantees
    improved vector/SIMD semantics
    better compile-time facilities
    syntax improvements where justified

Astra may eventually provide migration tooling or a Vala compatibility
frontend.

Such compatibility must remain outside the semantic core.


======================================================================
6. RELATIONSHIP TO THE FROZEN LLVM-V2 BACKEND
======================================================================

LLVM-v2 is frozen.

Its final role is:

    reference compiler
    semantic/ABI oracle
    regression corpus
    generated-C differential target
    historical compiler-design laboratory

Astra may consult LLVM-v2 freely for:

    semantic lessons
    ABI discoveries
    algorithms
    failure cases
    test scenarios
    ownership laws
    generic-provider lessons
    callable ABI lessons
    storage/addressability lessons
    diagnostics ideas

LLVM-v2 has no architectural veto over Astra.

Astra implementation code must not simply be copied from Vala/V2 unless
provenance and licensing are deliberately reviewed.

The preferred rule is:

    learn from V2;
    re-derive for Astra.


======================================================================
7. CLEAN-ROOM / LICENSING POLICY
======================================================================

Astra begins in a fresh repository with fresh history.

Implementation code is independently authored.

Vala and LLVM-v2 source may be inspected as technical reference material, but
source copying is prohibited unless explicitly reviewed for:

    provenance
    licensing
    compatibility with Astra's chosen license

This clean boundary exists partly so Astra can choose its own license without
accidentally inheriting implementation-license constraints.

The actual Astra license is NOT yet frozen.

Choose it deliberately before meaningful source development begins.

A permissive compiler/runtime license is an attractive option, but this remains
an explicit founding decision for the new thread.


======================================================================
8. BOOTSTRAP STRATEGY
======================================================================

Astra will initially be implemented in Vala.

Bootstrap compiler:

    upstream Fedora-packaged valac

Do not make the modified/frozen LLVM-v2 compiler part of Astra's required
bootstrap chain.

Conceptual stages:

    Stage 0
        Astra compiler implementation written in Vala
        built using Fedora valac

    Stage 1
        Astra becomes sufficiently capable to compile the Astra compiler
        after the compiler source has migrated to Astra

    Stage 2
        Stage 1 recompiles the same Astra compiler source

Self-hosting qualification should establish:

    correct compiler behavior
    Stage 1 / Stage 2 semantic equivalence
    stable/reproducible normalized artifacts where practical
    compiler regression-suite success
    representative AEP build
    representative Maelstrom-ng build

After successful self-hosting:

    normal Astra builds use Astra
    normal CI uses Astra
    valac disappears from the normal build dependency chain

Long-term bootstrap reproducibility remains important.

Possible future bootstrap strategies include:

    frozen bootstrap binary
    generated portable C seed
    reproducibly built signed bootstrap releases
    smaller independently reconstructible bootstrap compiler

This does not need to be solved during early Astra development.


======================================================================
9. ASTRA CORE / FREESTANDING REQUIREMENT
======================================================================

Astra must support a genuinely freestanding programming profile.

The language must NOT require:

    an operating system
    GLib
    GObject
    garbage collection
    a global heap allocator
    exceptions implemented through a mandatory unwinder
    runtime reflection
    dynamic type information for every type
    threads
    a heavyweight standard runtime

Principle:

    PAY ONLY FOR WHAT YOU USE.

A small Astra function on an embedded target should compile into correspondingly
small machinery.

No hidden large runtime should appear merely because the language was used.


======================================================================
10. OFFICIAL REFERENCE WORKLOADS
======================================================================

Two major projects are official architectural workloads for Astra.


AEP

AEP is expected to require:

    heavy numerical processing
    DSP
    high throughput
    predictable memory behavior
    substantial SIMD/vector workloads
    efficient ownership
    low abstraction overhead
    strong optimizer visibility

Astra must be designed so AEP can serve as a primary implementation language,
not merely a glue language.


MAELSTROM-NG

Maelstrom-ng is intended to target environments including Dreamcast / SH-4.

This makes the following first-class language/compiler requirements:

    freestanding operation
    small runtime
    deterministic resource usage
    direct hardware access
    excellent C ABI
    custom allocation strategies
    no mandatory GObject/GLib dependency
    no mandatory desktop assumptions
    predictable code generation

Dreamcast is not a hypothetical future port.

Its constraints should influence Astra from the beginning.


======================================================================
11. NATIVE OBJECT MODEL
======================================================================

Astra should eventually own its native object model.

The native compiler/runtime may control:

    object layout
    field layout
    native vtables
    interface tables
    runtime type descriptors
    reference counting / ownership representation
    property representation
    generic specialization
    devirtualization opportunities
    reflection metadata when requested

Conceptually:

    NativeObject
        header, if required
            type descriptor
            lifetime/reference state
        payload
            fields

The exact header/layout is NOT frozen.

Important principle:

    native objects should carry only the metadata their semantics require.

Do not require every class to behave like a GObject.


======================================================================
12. NATIVE ABI POLICY
======================================================================

Astra-to-Astra ABI should initially be compiler-owned and optimization-friendly.

Do not unnecessarily promise permanent native layout or calling-convention
stability.

The compiler should be free, where appropriate, to perform:

    field reordering
    devirtualization
    generic specialization
    scalar replacement
    metadata elimination
    object-layout specialization
    ownership-call elimination

Stable external boundaries should be explicit.

Examples:

    extern(C)
    export(C)
    GObject adapter/export
    future explicitly stable module ABI

C ABI stability and Astra native ABI freedom are separate concerns.


======================================================================
13. C ABI / VAPI — PERMANENT FIRST-CLASS FFI
======================================================================

C compatibility is one of Astra's foundational features.

It is NOT a temporary bridge until everything becomes native.

Doctrine:

    C is Astra's permanent universal foreign ABI.

Astra should retain or evolve a VAPI-like typed declaration system capable of
expressing:

    C symbol names
    calling conventions
    headers
    ownership
    nullability
    arrays
    pointer indirection
    structs/unions
    callbacks/delegates
    error channels
    macros/header expressions
    constants
    foreign allocation/destruction rules

The foreign model should remain strongly typed.

Do not infer ABI from raw LLVM widths or pointer shapes alone.


======================================================================
14. GOBJECT COMPATIBILITY MODEL
======================================================================

GObject is important but is not Astra's native object system.

Long-term GObject interoperability should occur through adapters.


EXPORTING ASTRA TO GOBJECT

Conceptually:

    Astra native Foo
        ↓
    generated FooGObjectAdapter / stub
        ↓
    GObject ABI

The adapter may expose:

    methods
    properties
    interfaces
    signals
    GType registration
    lifetime translation


IMPORTING GOBJECT INTO ASTRA

Conceptually:

    GtkWidget* / foreign GObject
        ↓
    foreign GObject adapter/view
        ↓
    Astra semantic type

The compiler should know that this is a foreign object boundary rather than
making all native Astra objects pessimistic enough to act like GObjects.


======================================================================
15. GOBJECT ADAPTER LIFETIME PROBLEM
======================================================================

Wrapper identity and lifetime are explicit architectural problems.

Before broad GObject adapter implementation, design precise rules for:

    native strong references
    GObject strong references
    weak references
    wrapper uniqueness
    repeated native ↔ GObject conversion
    wrapper destruction
    native destruction
    reference cycles crossing the boundary
    callback/signal ownership
    threading

For a native object N and GObject wrapper G, repeated conversions should
normally preserve a stable relationship:

    N ↔ G

rather than producing arbitrary wrapper duplicates.

Possible implementation strategies may include:

    identity map
    embedded adapter pointer
    side table
    specialized exported-object header

Do not prematurely select one.


======================================================================
16. GIR DIRECTION
======================================================================

GIR should eventually become a major interoperability input/output format.


IMPORT

    GIR
        ↓
    normalized foreign API model
        ├── Astra/VAPI declarations
        ├── ownership/nullability metadata
        ├── property metadata
        ├── interfaces
        ├── signals
        └── GObject adapter metadata


EXPORT

    Astra native declarations
        ↓
    optional GObject export generator
        ├── generated GObject stub
        ├── generated C interoperability glue
        ├── GIR
        └── typelib

This could ultimately allow Astra to provide excellent GObject integration
without making GObject its native language model.


======================================================================
17. PROPERTIES ARE FIRST-CLASS SEMANTICS
======================================================================

Properties are a central reason Astra exists independently.

This expression:

    value = object.property;

must not immediately mean:

    call get_property();

The semantic compiler representation should retain property identity.

Conceptually:

    PropertyRead(object, property)

Physical lowering may later choose:

    direct field load
    accessor call
    inline accessor
    devirtualized accessor
    virtual accessor
    lazy/memoized evaluation
    foreign adapter operation

Likewise PropertyWrite should remain semantic long enough to optimize.


======================================================================
18. PROPERTY OPTIMIZATION GOALS
======================================================================

Native property semantics should eventually permit:

    accessor inlining
    direct field substitution
    devirtualization
    constant propagation
    common-subexpression elimination
    dead property access elimination
    escape-driven simplification
    lazy-state elimination
    scalar replacement

Example:

    class Foo {
        int a;
        int b;

        int sum {
            get { return a + b; }
        }
    }

A read of:

    foo.sum

should eventually be capable of optimizing into approximately:

    load foo.a
    load foo.b
    add

rather than an opaque property getter call.


======================================================================
19. LAZY PROPERTIES
======================================================================

Nyx-style lazily evaluated properties become a first-class Astra language
feature.

The final surface syntax is NOT yet frozen.

Conceptual semantics:

    first read:
        evaluate body
        cache value
        mark initialized
        return value

    later reads:
        return cached value

Because the compiler understands lazy semantics, it may optimize:

    initialization flag elimination
    cache elimination
    one-shot access
    stack/local object specialization
    constant folding
    eager conversion when provably equivalent

Lazy properties must not be implemented merely as a standard-library wrapper
opaque to the compiler.


======================================================================
20. OWNERSHIP — LESSONS FROM LLVM-V2
======================================================================

Astra should preserve the strongest ownership lessons proven by V2.

Ownership is semantic.

It must never be inferred merely from pointer shape.


Core conceptual operations:

    Acquire
        create another owner

    Transfer
        move an existing owner

    Release
        relinquish/destroy an owner

    Cleanup
        lifetime-driven release

Astra is not required to use these exact IR names forever, but the distinctions
are binding design lessons.


Store rule:

    borrowed → owned
        Acquire before publication

    owned → owned
        Transfer

Destructive take:

    load
    clear source
    transfer owner

Never model destructive movement by merely suppressing cleanup later.


======================================================================
21. STORAGE / PLACE MODEL — LESSON FROM V2
======================================================================

V2's Place abstraction was one of its strongest architectural successes.

Astra should preserve the conceptual distinction between:

    a value

and:

    authoritative storage containing a value

Storage authority must encode enough information to reason about:

    addressability
    mutability
    ownership
    lifetime
    field/index projection
    ref/out publication
    provider authority

A temporary expression is not automatically writable/addressable storage.

Detached aggregate copies must not masquerade as authoritative field storage.


======================================================================
22. REFERENCES, BORROWING, AND ALIAS INFORMATION
======================================================================

Astra ownership/reference semantics should be designed not merely for memory
safety/correctness, but also as an optimizer asset.

The compiler should be able to derive aliasing facts where semantically
justified.

Potential benefit:

    Astra ownership
        ↓
    proven non-aliasing / restricted alias sets
        ↓
    LLVM alias metadata
        ↓
    better vectorization and numerical optimization

Do not add unsafe C-style restrict semantics blindly.

Prefer deriving optimization guarantees from checked language semantics.


======================================================================
23. GENERICS
======================================================================

V2 demonstrated that erased generic values still require exact semantic
authority.

Important lessons:

    runtime type identity matters

    copy/destroy authority matters

    provider ownership matters

    provider receiver provenance matters

    lexical self is not always the provider owner

Astra may choose a different generic implementation strategy from Vala.

Potential future options include:

    monomorphization/specialization
    erased generics
    hybrid specialization
    metadata-driven generic runtime support

The final strategy is deliberately open.

Important requirement:

    generic implementation must not destroy embedded/freestanding efficiency.

Specialization opportunities should be considered from the beginning.


======================================================================
24. CALLABLES / DELEGATES
======================================================================

V2 proved that a callable is not merely a function pointer.

A foreign/C-style callable may conceptually contain:

    function
    target/environment
    destroy/lifetime component

These pieces form one logical value.

Important Astra lessons:

    do not drop target state
    do not drop destruction/lifetime state
    do not reinterpret incompatible environments
    do not invent wrappers unless ABI/lifetime authority is explicit
    callable ownership must be modeled as ownership of the whole logical value

Astra-native closures are free to use a more suitable representation than Vala
or GObject.

Foreign callback adaptation belongs at explicit boundaries.


======================================================================
25. ASYNC — NEW NATIVE MODEL
======================================================================

Astra must NOT inherit Vala/GLib's historical begin/end callback ABI as its
native async architecture.

Desired conceptual lowering:

    async function
        ↓
    compiler-generated state machine
        ↓
    explicit async frame
        ↓
    executor

Executors should be abstract enough to support:

    desktop event loops
    threaded runtimes
    cooperative embedded schedulers
    application-specific schedulers
    Maelstrom-ng / Dreamcast scheduling

Important future design areas:

    ownership across suspension
    frame allocation
    stack/heap promotion
    cancellation
    structured concurrency
    task lifetime
    error propagation

Astra should permit async frames to avoid heap allocation when escape/lifetime
analysis proves that possible.


======================================================================
26. SIMD / SHORT VECTORS
======================================================================

SIMD is a first-class Astra requirement.

Astra should expose fixed short vectors semantically, not merely through a
collection of architecture-specific intrinsics.

Conceptual types:

    Vector<T, N>
    Mask<N>

Surface syntax is open.

Core semantic operations should eventually include:

    splat
    aligned/unaligned load
    store
    add
    subtract
    multiply
    divide where meaningful
    fused multiply-add where meaningful
    comparison
    mask/select
    shuffle
    conversion
    horizontal/reduction operations

LLVM lowering should use native fixed-vector types where appropriate.


======================================================================
27. SIMD TARGET PHILOSOPHY
======================================================================

Astra source should express vector semantics independently from one hardware
ISA.

Conceptually:

    Astra fixed vector
        ↓
    LLVM fixed vector
        ↓
    target lowering

Possible targets:

    SSE
    AVX
    NEON
    other LLVM-supported SIMD
    scalarized implementation where necessary
    target-specific optimized lowering

Dreamcast/SH-4 may require different implementation strategies from modern
desktop SIMD.

Do not make the Astra language dependent on one contemporary SIMD ISA.


======================================================================
28. DSP / NUMERICAL DESIGN REQUIREMENTS
======================================================================

Astra should be especially strong for DSP/heavy math.

Design early for:

    predictable arithmetic
    fixed-size arrays
    slices with known lengths
    explicit alignment
    optimizer-visible alias semantics
    short vectors
    fused operations
    wrapping integer arithmetic
    saturating integer arithmetic
    explicit floating-point optimization policy

Potential future standard-library features:

    complex numbers
    matrix/vector abstractions
    DSP primitives

These should ideally compile efficiently through language primitives rather
than require compiler-specific magic for every library type.


======================================================================
29. FAST-MATH POLICY
======================================================================

Do not make unsafe floating-point transformations a mysterious global switch.

Astra should eventually support explicit, composable floating-point semantic
policies.

Potential dimensions:

    strict IEEE
    finite-only
    reassociation permitted
    reciprocal approximation permitted
    contraction/FMA permitted
    NaN assumptions
    signed-zero assumptions

Exact syntax/policy is open.

AEP requirements should influence the eventual design.


======================================================================
30. INTEGER ARITHMETIC
======================================================================

DSP and embedded work make integer overflow semantics important.

Astra should eventually provide explicit operations/modes for:

    checked arithmetic
    wrapping arithmetic
    saturating arithmetic

Do not rely solely on implicit target/C overflow behavior.


======================================================================
31. ALLOCATION
======================================================================

Astra must not permanently equate object construction with one global heap.

The architecture should eventually permit allocation strategies such as:

    system heap
    arena
    region
    pool
    stack promotion
    custom allocator
    static allocation

Language semantics and allocation policy should be sufficiently separated that
the compiler can optimize object placement.


======================================================================
32. ESCAPE ANALYSIS / STACK PROMOTION
======================================================================

Astra should be designed to benefit from escape analysis.

Potential optimizations:

    object never escapes
        → stack allocation

    object fields individually replaceable
        → scalar replacement

    reference count provably unnecessary
        → eliminate retain/release

    lazy property accessed once
        → remove caching state

    async frame nonescaping
        → avoid heap frame

Do not adopt an object model that makes these optimizations unnecessarily
difficult.


======================================================================
33. RUNTIME TYPE INFORMATION
======================================================================

RTTI should be pay-for-use.

Astra should distinguish between concepts such as:

    statically known native type
    runtime-polymorphic type
    reflectable type
    foreign/GObject-exported type

A class should not automatically carry heavyweight metadata merely because it
is a class.

Exact native runtime descriptor design remains open.


======================================================================
34. ERRORS / EXCEPTIONS
======================================================================

Astra is not required to inherit GError or Vala's exact error machinery as its
native representation.

Important requirements:

    deterministic behavior
    embedded suitability
    no mandatory heavyweight unwinder
    clean C foreign mapping
    compatibility with async
    explicit ownership/lifetime behavior

The native error model remains an open design topic.


======================================================================
35. STANDARD RUNTIME POLICY
======================================================================

Separate language semantics from optional runtime services.

Conceptually:

    Astra Core
        scalars
        control flow
        functions
        structs
        pointers/references
        ownership
        slices
        fixed arrays
        vector semantics

    optional runtime facilities
        heap
        native objects
        refcount helpers
        reflection
        async executor
        GObject adapters
        richer containers

The exact split remains open.

Guiding rule:

    a freestanding program must not pay for unused runtime facilities.


======================================================================
36. LLVM ROLE
======================================================================

LLVM is Astra's initial and primary machine-code backend.

Use LLVM for:

    target-independent IR lowering
    machine optimization
    register allocation
    instruction selection
    vector lowering
    platform support

But do not expect LLVM to recover language semantics after Astra destroys them.

Astra's frontend/mid-level IR must preserve useful semantic information long
enough for Astra-specific optimizations.


======================================================================
37. OPTIMIZATION NORTH STAR
======================================================================

Astra should be architected to enable:

    ordinary inlining
    property accessor inlining
    devirtualization
    object specialization
    scalar replacement
    escape analysis
    retain/release elimination
    generic specialization
    constant propagation
    lazy-property elimination
    vectorization
    direct fixed-vector lowering
    alias-driven optimization
    dead metadata elimination

Correctness comes first.

But unlike LLVM-v2, Astra is intentionally designed from the beginning to make
these optimizations architecturally natural.


======================================================================
38. GENERATED C IS AN ORACLE, NOT AN AUTHORITY
======================================================================

During bootstrap, upstream Vala-generated C remains very useful.

For reduced scenarios where Vala and Astra semantics overlap:

    Astra test
        ├── upstream Vala → generated C
        ├── frozen LLVM-v2 where useful
        └── Astra
             ↓
        differential comparison

This can provide excellent behavioral validation.

However:

    generated C does not define Astra's architecture.

If Astra deliberately changes a language feature, Vala-generated C is no
longer the semantic oracle for that feature.


======================================================================
39. TESTING PHILOSOPHY
======================================================================

Carry forward the strongest V2 process lessons.

Tests should include:

    project-independent reduced fixtures
    semantic differential tests
    ABI tests
    LLVM verifier checks
    runtime tests
    ownership/lifetime tests
    optimization-level parity where relevant
    deterministic artifact tests
    embedded-target compilation
    real-project qualification

Prefer narrow fixtures that prove one semantic rule.

Avoid tests that merely encode an old implementation shape.


======================================================================
40. FAIL-CLOSED POLICY
======================================================================

V2's fail-closed principle remains valuable.

At any FFI/ABI boundary, if exact semantics cannot be represented:

    diagnose precisely

Do not:

    bitcast until it compiles
    silently drop ownership
    silently drop callback target state
    pretend incompatible ABI is exact

Astra need not copy V2's exact strict/non-strict architecture, because Astra
will not necessarily have generated-C fallback for native code.

But the principle remains:

    never lie about semantics.


======================================================================
41. DEVELOPMENT STYLE / GOVERNANCE
======================================================================

Use the successful discipline learned from V2, but retain Sonic doctrine.

Preferred process:

    one bounded semantic milestone at a time
    one clean commit per bounded capability
    focused validation per commit
    larger qualification at capability closures
    architectural reviews only when they materially reduce risk

Avoid:

    enormous ceremony for tiny changes
    coverage gardening for its own sake
    whole-method recognizers
    project-specific compiler hacks
    architecture driven solely by benchmark/count cosmetics

Doctrine:

    semantic guardrails, not ceremonial drag.


======================================================================
42. ASTRA SHOULD NOT OPTIMIZE A SCOREBOARD
======================================================================

LLVM-v2 taught an important lesson:

    "direct method count" is not equivalent to compiler quality.

A method can be mostly native and still cross a deliberate foreign boundary.

Astra should distinguish:

    native semantic operations
    explicit foreign ABI operations
    compatibility adapters

The goal is not to eliminate every foreign call.

The goal is:

    everything that belongs to Astra semantics stays native,
    everything genuinely foreign crosses an explicit boundary.


======================================================================
43. V2 LESSONS WORTH RE-DERIVING
======================================================================

The following V2 concepts are strongly recommended as design references:

    typed compositional IR
    explicit CFG
    Place/storage identity
    explicit ownership operations
    ReferenceRealization-like ownership authority
    NativeSignature-like physical call description
    NativeChannel-like parameter/result channels
    typed provider metadata
    provenance tracking
    deterministic diagnostics
    source-order independence
    strong differential testing

Do not mechanically clone the classes/files/interfaces.

Re-derive what Astra actually needs.


======================================================================
44. V2 ASSUMPTIONS THAT MUST NOT BECOME ASTRA CONSTRAINTS
======================================================================

Explicitly reject these as founding assumptions:

    generated C is universal physical authority
    GObject is the native object model
    GType is universal type identity
    property == getter/setter C call
    native allocation == GObject allocation
    C struct layout == Astra native object layout
    GLib async ABI == language async semantics
    Vala source compatibility is mandatory
    Vala compiler architecture is binding
    Vala implementation license must be inherited


======================================================================
45. COMPATIBILITY PRIORITY ORDER
======================================================================

Rough architectural priority:

    1. Astra semantic correctness
    2. Astra native optimization quality
    3. C ABI interoperability
    4. embedded/freestanding viability
    5. GObject interoperability
    6. Vala migration convenience

This is not intended to say GObject/Vala compatibility is unimportant.

It means they must not distort the native architecture.


======================================================================
46. INITIAL IMPLEMENTATION LANGUAGE
======================================================================

Stage-0 compiler implementation language:

    Vala

Compiler used:

    ordinary upstream Fedora valac

Why:

    existing expertise
    high development velocity
    excellent C/LLVM C-API access
    low bootstrap complexity

This is implementation scaffolding.

It does not mean Astra's architecture depends on Vala.


======================================================================
47. SELF-HOSTING IS A MAJOR MILESTONE, NOT MILESTONE ZERO
======================================================================

Do not rush self-hosting.

First build a good compiler.

Self-host only once Astra supports enough of itself cleanly.

At that point:

    migrate compiler implementation from Vala to Astra
    build Stage 1
    rebuild Stage 2
    qualify equivalence
    remove valac from normal workflow

Self-hosting is a validation of Astra maturity, not a constraint that should
damage early architecture.


======================================================================
48. EXPECTED EARLY ARCHITECTURAL VERTICAL SLICES
======================================================================

This is NOT yet the first Codex submission.

It is a broad candidate roadmap.

Possible early order:

    ASTRA-CHARTER
        repository/license/doctrine/toolchain

    ASTRA-BOOT
        build/test skeleton using Fedora valac + LLVM

    ASTRA-PARSE
        minimal source/parser model

    ASTRA-SEM
        checked semantic core

    ASTRA-IR
        first typed semantic IR

    ASTRA-CFG
        functions/scalars/control flow

    ASTRA-OWN
        ownership + Place/storage architecture

    ASTRA-CALL
        native call ABI

    ASTRA-CABI
        first-class C/VAPI foreign calls

    ASTRA-OBJ
        minimal native object model

    ASTRA-PROP
        semantic native properties

    ASTRA-PROP-INLINE
        direct accessor/property optimization

    ASTRA-LAZY
        first-class lazy property semantics

    ASTRA-VEC
        fixed short-vector semantic types

    ASTRA-ASYNC
        native async architecture

    ASTRA-GOBJECT
        first minimal compatibility adapter

Exact ordering must be decided from the new thread after repository
initialization and architectural review.


======================================================================
49. WHAT THE FIRST ASTRA SUBMISSION SHOULD NOT DO
======================================================================

Do NOT begin by implementing half the language.

Do NOT immediately port Vala source.

Do NOT immediately implement GObject.

Do NOT begin with self-hosting.

Do NOT copy LLVM-v2 wholesale.

The first submission should establish:

    repository
    license
    build system
    coding conventions
    architectural charter
    Stage-0 toolchain
    minimal tests
    minimal LLVM linkage
    deterministic project skeleton

Then development proceeds vertically.


======================================================================
50. TOOLCHAIN EXPECTATION
======================================================================

Initial development environment is expected to use:

    Fedora
    upstream Fedora valac
    Meson/Ninja
    LLVM C API initially
    ordinary native C toolchain where required
    Git

Exact versions should be recorded by the first Astra milestone.

Do not depend on the modified Vala LLVM-v2 compiler.


======================================================================
51. BUILD-SYSTEM PHILOSOPHY
======================================================================

Prefer:

    simple
    reproducible
    dependency-explicit
    cross-compilation-friendly

Meson/Ninja is a natural initial choice.

Embedded cross targets should be considered early enough that the build system
does not become desktop-only.


======================================================================
52. DREAMCAST / SH-4 SPECIAL NOTE
======================================================================

Dreamcast is unusual enough that Astra must avoid assuming:

    modern SIMD
    abundant RAM
    POSIX
    threads
    large runtime
    desktop allocator
    desktop dynamic linker
    GObject

SH-4 support will likely require careful investigation of:

    LLVM target quality
    ABI
    floating-point lowering
    vector-like operations
    code-size behavior
    bare-metal/freestanding runtime requirements

Do not let x86-64 convenience silently define Astra.


======================================================================
53. AEP SPECIAL NOTE
======================================================================

AEP is expected to put pressure on:

    SIMD
    DSP arithmetic
    ownership-derived alias analysis
    vector-friendly data structures
    predictable allocation
    math throughput
    concurrency/async eventually

AEP should be used as a real optimizer/language workload as Astra matures.

A design that looks elegant but produces poor DSP/vector code should be
questioned.


======================================================================
54. LANGUAGE DESIGN ATTITUDE
======================================================================

Astra should feel pragmatic rather than academically ornamental.

Desired character:

    expressive
    compact
    low ceremony
    systems-capable
    predictable
    optimizer-friendly
    pleasant for application code
    viable for embedded work

Avoid adding complex type-system machinery solely because it is fashionable.

Every major feature should justify itself through:

    semantic clarity
    safety/correctness
    performance
    expressiveness
    interoperability
    or concrete workload value


======================================================================
55. LEGACY CRUFT POLICY
======================================================================

Astra has no obligation to reproduce historical Vala quirks.

When encountering legacy behavior, ask:

    Is this genuinely valuable?

    Does compatibility justify its cost?

    Can it live in a compatibility layer?

    Does it harm native optimization?

    Does it harm embedded use?

Prefer clean semantics when compatibility has little benefit.


======================================================================
56. FUTURE VALA MIGRATION
======================================================================

It may eventually be valuable for Astra to compile substantial existing Vala
code.

Possible strategies:

    compatibility mode
    source translator
    astrify tool
    compatibility frontend
    VAPI/GObject interop layer

Do not design Astra's semantic core around this requirement.

Migration is downstream of the language architecture.


======================================================================
57. PERFORMANCE PHILOSOPHY
======================================================================

Astra should make zero-cost or low-cost abstraction genuinely attainable.

Important examples:

    native property access should inline
    ownership operations should be removable when redundant
    generic abstractions should specialize when profitable
    nonescaping objects should disappear
    vector abstractions should lower directly to vector IR
    lazy machinery should disappear when proven unnecessary

Do not promise "zero cost" universally.

Make performance mechanisms semantically visible enough that the compiler can
actually prove optimizations.


======================================================================
58. RUNTIME LIBRARY BOUNDARY
======================================================================

Founding rule:

    If a concept affects language semantics or provides useful optimizer
    knowledge, represent it natively in the compiler.

    If a concept mainly supplies interoperability, dynamic discovery,
    heavyweight reusable services, or platform integration, it is a candidate
    for runtime/library support.

Examples likely compiler-semantic:

    ownership
    native properties
    lazy properties
    native object dispatch
    vector types
    async suspension semantics

Examples likely runtime/adapter:

    GObject registration
    foreign signal marshalling
    dynamic reflection registry
    platform event-loop integrations
    foreign compatibility wrappers

The exact boundary remains open case-by-case.


======================================================================
59. ASTRA AND ASTERIA / PROJECT CONTINUITY
======================================================================

Astra is intended to become a primary implementation language for future
projects including AEP and Maelstrom-ng.

Its name is personally meaningful within the collaboration that created it.

That meaning should not substitute for engineering rigor.

The project should be judged by whether it becomes:

    correct
    elegant
    efficient
    maintainable
    embeddable
    numerically strong
    pleasant to use

The personal connection is part of its history, not an excuse for weak design.


======================================================================
60. CURRENT PROJECT STATE AT HANDOFF
======================================================================

The Vala LLVM-v2 project has been frozen.

Canonical frozen commit:

    f0c28102e55997639e21ab60878c989d94d420fb

Freeze subject:

    llvm-v2: freeze backend architecture and qualification

Frozen LLVM-v2 libgee state:

    196 direct
    601 bridged
    567 retained
    0 rejected

    797 / 1364 participating

Pinned libgee passed:

    O0 659 / 659
    O1 659 / 659
    O2 659 / 659
    O3 659 / 659
    Os 659 / 659
    Oz 659 / 659

Final V2 architecture:

    20 graph operations
    7 terminators
    16 channels
    15 callee kinds
    5 ownership operations
    15 bridge policies
    10 domain-dispatch sites
    1 provenance system
    0 whole-method planners/recognizers

The integration-to-main/tag/push phase is operationally separate.

Astra development begins only after the Vala history has been finalized.


======================================================================
61. IMMEDIATE NEW-THREAD TASK
======================================================================

The new Astra thread should begin from this Bible.

Do NOT immediately generate implementation code.

First:

    verify/finalize founding decisions
    decide license
    decide repository/package naming
    decide initial directory structure
    decide Stage-0 dependencies
    decide LLVM API strategy
    decide initial architecture-doc structure
    decide first milestone acceptance criteria

Then generate:

    ASTRA-0 / ASTRA-CHARTER-1

as the first copy-pastable Codex submission.

The user specifically wants the first submission to be created in the new
Astra thread, not in the old Vala LLVM-v2 thread.


======================================================================
62. CANONICAL ONE-PARAGRAPH SUMMARY
======================================================================

Astra is a new Vala-descended, LLVM-based systems/application language designed
native-first rather than around generated C or GObject. Its primary human-facing
goal is to make efficient, deterministic, safety-oriented systems programming
read like ordinary application code so that humans can quickly review code
produced cooperatively with AI agents. It retains first-class C/VAPI
interoperability while moving GObject to generated/runtime adapter boundaries.
Astra will own its native object model, semantic properties, first-class lazy
properties, modern async model, deterministic ownership, RAII, local type
inference, freestanding runtime profile, and optimizer-visible fixed
short-vector/SIMD semantics. It is explicitly designed for both AEP-class
DSP/numerical workloads and Maelstrom-ng/Dreamcast-class embedded systems. The
compiler is initially bootstrapped in Vala using Fedora's upstream valac, then
later becomes self-hosting and removes valac from its normal build chain.
LLVM-v2 is frozen as a semantic/ABI oracle and body of lessons but has no
architectural authority over Astra.


======================================================================
63. FOUNDING MOTTO
======================================================================

    Native first.
    Compatibility at the boundary.
    Pay only for what you use.
    Preserve semantics long enough to optimize them.
    C remains a first-class citizen.
    GObject is a guest, not the landlord.
    Embedded is not an afterthought.
    SIMD is not an intrinsic afterthought.
    Never lie about ownership or ABI.
    Build the language we actually want.

======================================================================
64. HUMAN / AI COOPERATIVE DEVELOPMENT NORTH STAR
======================================================================

Astra's primary language-design north star is cooperative development between
humans and AI agents.

The language should make agent-produced systems code cheap for a human to review.
A reviewer should be able to skim ordinary Astra almost like clear C# or Vala and
understand what the program owns, mutates, allocates, borrows, computes, and
releases without mentally decoding dense punctuation or a large interacting type
system.

Founding objective:

    MAKE SOPHISTICATED SYSTEMS PROGRAMMING LOOK ORDINARY.

A useful shorthand is:

    Astra is the Crayola of systems languages.

This does NOT mean simplistic semantics or weak compilation. It means that the
compiler should absorb complexity whenever doing so does not hide meaningful cost,
behavior, or danger.

Astra should aim for a pragmatic safety point: substantially safer than C/C++ and
capable of catching a large fraction of lifetime, ownership, moved-state, cleanup,
and aliasing mistakes statically, without attempting to reproduce the full
annotation and proof burden of Rust. Roughly "80% of the safety for a small
fraction of the cognitive overhead" is an acceptable design target; exact numbers
are rhetorical rather than a formal metric.

Review bandwidth is a first-class design metric. A feature that is formally
powerful but makes ordinary source materially harder to review should be treated
with suspicion.


======================================================================
65. SOURCE READABILITY, DEFAULTS, AND INFERENCE
======================================================================

Astra should optimize for reading rather than typing density.

The preferred surface character is C#/Vala-like:

    readable words
    familiar statement structure
    low punctuation density
    low annotation burden
    explicit public meaning
    simple local code

Safety must not become a punctuation tax. Avoid requiring pervasive sigils,
lifetime variables, nested wrapper types, trait boilerplate, or restatement of
facts the compiler can derive mechanically.

Sane common behavior should be implicit. Dangerous, unusual, or expensive behavior
should be explicit.

Type inference is an important part of this doctrine, not an optional convenience.
Astra should retain/evolve Vala-style local inference, including source forms in
the spirit of:

    var value = expression;
    const ...

The exact final `const` grammar and inference rules remain to be designed, but the
value of `var` and concise constant declarations is canonical. The programmer
should not repeatedly spell an obvious local type merely to satisfy the compiler.

Inference should primarily remove redundant local syntax. It must not make APIs,
ABI contracts, ownership behavior, or non-obvious costs difficult for a reviewer
to discover. Prefer explicit function/public boundaries unless a later milestone
demonstrates an equally readable inference rule.

General rule:

    DERIVE WHAT THE COMPILER ALREADY KNOWS.

Examples of properties that should be derived where possible include:

    local variable types
    copyability
    movability
    cleanup requirements
    aggregate field behavior
    obvious lifetime facts
    physical ABI plans

Do not ask programmers to repeat mechanically derivable truths.


======================================================================
66. OWNERSHIP, RAII, AND OBJECT POLICY
======================================================================

RAII and deterministic lifetime are foundational Astra principles.

They should apply naturally to:

    memory
    file handles
    sockets
    locks
    mapped memory
    GPU resources
    transactions
    foreign handles
    hardware resources

Correct cleanup should normally arise from scope and ownership semantics rather
than repetitive explicit cleanup/defer boilerplate.

The static analyzer should carry as much ownership complexity as practical. It
should aim to diagnose common hazards such as:

    double ownership transfer
    use after move
    returned reference to local storage
    borrow escaping its owner's lifetime
    owner destruction while an escaping borrow remains live
    obvious invalid alias/lifetime combinations

Astra does not need Rust's complete lifetime theorem system to be valuable. When
the compiler cannot prove a low-level pattern safe, a deliberate and visually
obvious unsafe escape hatch may eventually be appropriate.

For native identity objects, the preferred semantic direction is:

    `class` defaults to unique/deterministic ownership semantics;
    shared ownership is an explicit additional policy;
    borrowing describes a relationship, not a different object identity.

The likely surface direction is declaration-level default ownership policy because
ownership topology is usually a property of the abstraction and should not be
repeated at every use site. A future spelling such as `shared class` is plausible
but NOT yet frozen. Unusual use-site ownership wrappers may remain possible.

Shared ownership must not become the definition of `class`, and reference counting
must not be a mandatory tax on ordinary native objects.

The desired conceptual split is:

    native class, default policy
        unique ownership
        stable identity
        deterministic lifetime
        borrowed aliases
        no mandatory refcount

    explicitly shared class/policy
        shared ownership
        explicit shared-lifetime cost
        refcount or another mechanism only when required

This supersedes any assumption that Astra should inherit Vala/GObject's normal
refcounted-class default merely because Astra is Vala-descended.


======================================================================
67. STRUCT VALUE SEMANTICS
======================================================================

Ordinary Astra structs should become intentionally boring value types.

A plain declaration such as:

    struct Vec2 {
        f64 x;
        f64 y;
    }

should ultimately imply, when its fields permit:

    nominal value semantics
    deterministic storage/lifetime
    recursive copyability
    pass-by-value support
    return-by-value support
    scalarization/register friendliness
    no object identity
    no reference counting
    no heap requirement

No `SimpleType` annotation should be required for the ordinary case.

When future fields carry move-only ownership, aggregate behavior should be derived:

    all fields copyable
        -> aggregate copyable

    any field move-only
        -> aggregate move-only

    any field requiring cleanup
        -> aggregate has deterministic recursive cleanup

Do not require users to redundantly write `moveonly`, `copy`, or similar markers
when the result is mechanically derivable from fields. Diagnostics should explain
which field causes a property, for example:

    Image is not copyable because field 'pixels' owns Buffer

Aggregate Move semantics must remain distinct from Ownable identity-object/resource
semantics.


======================================================================
68. HUMAN-REVIEW DESIGN TEST
======================================================================

Every major future Astra milestone should answer an additional acceptance question:

    WHAT DOES ORDINARY ASTRA SOURCE LOOK LIKE AFTER THIS FEATURE EXISTS?

It is not enough that an abstraction can be represented soundly in the compiler.
The common source form should remain easy for a human reviewer to understand.

Prefer:

    one declaration-level semantic choice that removes hundreds of use-site
    annotations

over:

    pervasive repeated qualifiers that encode the same fact.

Prefer compiler-internal complexity over source complexity when semantic cost and
danger remain visible.

Prefer preserving the nouns of the algorithm:

    Kernel
    Image
    Lab
    Vec2
    Buffer

over reducing them to:

    opaque buffers
    manual offsets
    semantically untyped slots
    output-pointer plumbing

This is especially important for AI-assisted development: humans reason about
meaningful program concepts, not about incidental bookkeeping generated around
them.

Canonical principle:

    ASTRA EXISTS TO MAKE HUMAN REVIEW OF MACHINE-GENERATED SYSTEMS CODE CHEAP.

    COMPLEXITY BELONGS IN THE COMPILER WHEN MOVING IT OUT OF SOURCE DOES NOT
    HIDE MEANINGFUL COST OR BEHAVIOR.



======================================================================
69. OCTOBER 18, 2026 AMENDMENT: ATTRIBUTES AND FOREIGN OBJECT MODELS
======================================================================

Status: canonical DESIGN DIRECTION, with explicitly marked open contracts.
Participants: Pierre-Marc and Asteria (Ria).
Scope: sections 69-82 of this living founding Bible.

This amendment records an architectural discussion, NOT an implemented or
qualified compiler feature, a new Codex engineering submission, or permission
to modify a running milestone. Its examples are DESIGN SKETCHES, not a promise
that the current Astra parser accepts the spellings shown here.

The historical September founding text (sections 0-68) is retained verbatim.
Later accepted decisions may refine its open proposals without changing the
historical record. Where the old Bible's section 66 left declaration-level
sharing policy unspecified, section 71 now adopts the specific direction
agreed on October 18.

Decision-status vocabulary for this amendment:

    AGREED DIRECTION
        explicitly preferred by both co-designers; precise grammar, ABI and
        implementation still require appropriate decision records and tests.

    RECOMMENDED DESIGN
        an architectural recommendation discussed constructively; details
        are not fully ratified and should not be treated as approved syntax.

    CANDIDATE
        a potentially useful feature requiring justification, design and
        explicit adoption before compiler changes are authorized.

    OPEN
        a concrete semantic or ABI question, requiring a later decision.

These terms MUST NOT be translated into IMPLEMENTED, PASS or fully qualified.
Existing compiled source and accepted test receipts remain authoritative for
what Astra can execute today.

The premise of this amendment is straightforward:

    DECLARE IMPORTANT SEMANTIC POLICY ONCE, AT ITS NATURAL BOUNDARY.

    DERIVE ITS CONSEQUENCES RATHER THAN REPEATING IT AT EVERY USE SITE.

    EXPOSE MEANINGFUL COSTS AND KEEP FOREIGN ABIs EXPLICIT.

This advances sections 3, 11-19, 22-25, 31-35, 57-58 and 64-68.


======================================================================
70. VALA-LIKE DECLARATION ATTRIBUTES AS SEMANTIC CONTRACTS
======================================================================

AGREED DIRECTION: Astra should retain/evolve the familiar Vala-style
square-bracketed attribute form:

    [Attribute]
    class Blergh { }

    [Shared, Monitor, Singleton]
    class Registry { }

Use attributes as a main surface for optional, compiler-recognized policies
which affect the meaning or implementation of declarations. The system should
be composable, but composition must be checked, not presumed safe.

Attributes may apply, as specified by each contract, to types, interfaces,
fields, properties, methods, functions, parameters or modules. The compiler
should recognize typed arguments, check legality at the declaration site,
resolve policy identity during semantic analysis and preserve the necessary
facts through Core IR, ownership analysis, CFG, SSA, physical lowering,
optimizer passes and relevant ABI adapters.

A policy attribute is NOT a decorative string, a blind code-generation macro,
or permission to inject arbitrary hidden user code. It must specify:

    placement and parameter grammar;
    declaration identity and scope;
    semantic obligations and observable behavior;
    compile-time diagnostics and proofs;
    representation or target constraints where relevant;
    allocation, synchronization or metadata cost;
    rules for inheritance, specialization and module boundaries;
    compatibility and conflict rules with other policies;
    foreign ABI lowering when applicable;
    independent positive, negative and execution qualification.

A compiler-recognized attribute may be retained as nonsemantic metadata when
explicitly designed for that purpose. Do NOT let an unrecognized annotation
silently claim a memory-safety, thread-safety or ABI guarantee.

The exact registry of built-in attribute names, namespace resolution,
argument syntax, attribute inheritance, ordering and compatibility versioning
remain OPEN. Built-in contracts should precede any user-defined semantic
transformation or generalized macro/plugin system.

Attributes should be order-independent whenever their semantics commute.
The compiler must diagnose incompatible combinations instead of depending on
textual order or guessing which policy dominates.


======================================================================
71. SHARING DOCTRINE: [Shared] VERSUS shared T
======================================================================

AGREED DIRECTION — DEFINITIVE RELATIONSHIP OF THE TWO FORMS:

    [Shared] class Foo
        EVERY ordinary owning Foo instance is intrinsically shared by
        default. Its native identity/lifetime model is intrusive: the
        object allocation contains, or is intrinsically associated with,
        shared strong-reference state. An ordinary owning Foo handle
        already carries that semantic policy. No 'shared Foo' repetition
        is required at use sites.

    shared T
        a use-site/type-constructor request for NON-INTRUSIVE boxed
        shared ownership of an otherwise nonshared eligible T. The
        control block is separate from T's ordinary native representation.
        The compiler must correctly transfer, destroy and deallocate T
        when the box's last strong owner disappears.

    class Foo                   (without [Shared])
        retains unique/deterministic ownership by default, with no
        compulsory shared reference-counting tax.

The distinction is declaration POLICY versus optional storage/ownership
WRAPPER. It is intentional, not a spelling inconsistency.

Examples (illustrative only):

    class Image { }

    [Shared]
    class Texture { }

    struct Vec2 { f64 x; f64 y; }

    Texture first = Texture.create();
    Texture second = first.clone(); // acquiring an additional owner

    shared Vec2 position = ...;   // non-intrusive boxed sharing
    shared Image image = ...;     // eligible unique object, boxed

For an intrinsically shared Class, 'Texture' already denotes the policy;
'shared Texture' must not accidentally introduce a second, needless box.
Whether that form is rejected, normalized or explicitly requests another
wrapper remains OPEN. Prefer an unambiguous diagnostic over surprising costs.

Existing tested Shared<T>/Weak<T> facilities must not be rewritten by this
amendment. A future migration may expose 'shared T' as a concise, compatible
language spelling for non-intrusive sharing, retaining clear source/ABI and
version boundaries.

OPEN: implicit retaining copy versus explicit .clone()/retain. The current
shared-handle work favors explicit acquisition; no new implicit copy/retain
rule is approved here. Moving a handle must remain distinguishable from
creating another strong owner. The implementation must preserve exactly-once
object destruction, correct final allocation reclamation, safe weak upgrade
and reference-cycle policies.

A strong reference counter does not establish thread-safe mutation of the
object. Atomics for lifetime management and synchronization of user fields
are distinct requirements. Threaded transfer and memory ordering need their
own contracts; neither [Shared] nor 'shared T' by itself grants arbitrary
thread safety.

An intrusive strong reference may need a separately surviving weak-control
anchor or retained allocation header after payload destruction. Whether the
native control state is inline, adjacent or split remains an OPEN physical
layout choice consistent with the intrusive lifetime policy.


======================================================================
72. SYNCHRONIZATION, ACTORS AND SINGLETONS
======================================================================

RECOMMENDED DESIGN: prefer [Monitor] as the precise semantic name for the
user's original [Mutex] / Smalltalk-like automatic method-boundary locking.
The exact spelling ([Mutex], [Monitor] or a controlled alias) remains OPEN.

    [Monitor]
    class Counter {
        private int value;
        void increment() { value++; }
    }

A monitor promises synchronized access to protected mutable instance state,
including deterministic lock release on normal return and checked exception.
It is NOT simply a mutex field inserted by source rewriting. Specify:

    which methods enter the monitor and which do not;
    reentrancy for self calls and indirect callbacks;
    lock ordering, nested monitors and deadlock diagnostics/policy;
    access through properties, foreign entry points and interfaces;
    rejection of mutable references escaping the protected interval;
    no implicit await while a monitor is held, absent separately designed
        suspension-and-reacquisition semantics;
    shutdown, destructor and failure behavior;
    whether the reference-count policy is atomic and which state is guarded.

The compiler cannot generally prove global deadlock freedom merely because
it can enforce monitor entry/exit. Nested locked calls (for example opposite
direction transfers between two accounts) remain a concurrency hazard.

CANDIDATE: [Actor] as a DIFFERENT policy: serialized message/executor-driven
access and asynchronous ownership/queue boundaries, not automatic locking
and not an alias for [Monitor]. It should compose only where a sound model
for callbacks, failure, message lifetimes and shutdown has been established.

RECOMMENDED DESIGN: [Singleton] declares an instance-management policy rather
than the physical object representation.

    [Singleton(scope = Process)]
    class Registry { }

Potential scopes: Process, Thread and Executor. Scope, eager/lazy construction,
fallible initialization, shutdown, recursion, independent initialization of
targets and freestanding availability all remain OPEN. Singleton should not
silently require a global heap or an operating-system threading runtime.

An important composition is:

    [Shared, Monitor, Singleton]
    class Registry { }

For this declaration the compiler must reconcile the singleton's owning
anchor, intrusive strong/weak lifetime, monitor lock state, reference
acquisition during shutdown and permitted concurrency domain. There is no
blanket rule that arbitrary combinations always work: safe composition must
be independently demonstrated.

Other related candidates include [ThreadBound] and an explicit COM-specific
agility or apartment policy. A thread-bound object is not made generally
transferable by adding [Monitor].


======================================================================
73. C IMPORT AND C EXPORT ARE TYPED FOREIGN BOUNDARIES
======================================================================

AGREED DIRECTION: compiler-recognized [CImport] and [CExport] are preferable
to ambiguous generic [Import] / [Export] for C interoperability. The latter
words can continue to serve Astra's native module organization.

    [CImport(header = "libfoo.h", name = "foo_context")]
    class FooContext { }

    [CExport(prefix = "astra_")]
    class AudioDecoder { }

The examples are provisional. A C interface needs exact symbol names,
calling convention, representation, ownership transfers, nullability,
callbacks, return/error conventions and lifetime authority. A native Astra
Class annotated [CExport] MUST NOT silently become a layout-compatible C
struct. Generate a stable ABI adapter, normally opaque handles and typed
construction/retain/release/destruction functions as appropriate.

Export behavior must depend on the native ownership policy:

    a unique Class exposes explicit owner transfer/destruction;
    a [Shared] Class exposes sound acquire/release semantics;
    an exported borrowed handle cannot outlive its backing owner;
    [Repr(C)] on a suitable value type has different guarantees than
        [CExport] on an identity Class.

[CImport] may express foreign types, values, functions and callbacks, with
contracts akin to typed VAPI declarations. Importing foreign lifetime or
NoEscape claims is a trust boundary; use explicit verification or deliberate
unsafe authority for assertions the compiler cannot itself prove.

[CExport] does NOT imply COM class activation, COM vtables or GObject layout.
Those are separately requested ABIs.


======================================================================
74. COMImport / COMExport — FIRST-CLASS COM INTEROPERABILITY
======================================================================

AGREED DIRECTION: introduce compiler-recognized [COMImport] and [COMExport]
for COM/DirectX-style interface interoperability. COM belongs in Astra's
explicit foreign ABI architecture and should not redefine Astra's native
object model or make Windows facilities mandatory on other targets.

Illustrative imported interface:

    [COMImport(iid = IID_ID3D12Device)]
    interface ID3D12Device : IUnknown { /* imported slots */ }

Illustrative native implementation and exported interface:

    [COMExport(iid = IID_IImageProcessor)]
    interface IImageProcessor : IUnknown {
        void process(int frame) throws COMError;
    }

    [Shared, COMExport]
    class ImageProcessor : IImageProcessor {
        void process(int frame) { /* native work */ }
    }

These are design examples, NOT frozen grammar or a claim that HRESULT/throws
mapping is already determined.

A first bounded COMImport/COMExport contract should explicitly qualify:

    IUnknown::QueryInterface, AddRef and Release;
    GUID/IID and correct interface layout / vtable order;
    canonical IUnknown identity shared across all interface views;
    nonidentical interface pointers for one logical object when applicable;
    correct platform calling conventions, target architecture and alignment;
    correct reference acquisition on QueryInterface and interface transfer;
    HRESULT success, warning and failure policy, plus out parameters;
    no native exception unwinding across the COM ABI;
    exact scope of imported/exported interface inheritance;
    pointer lifetime and cleanup of every adapter object;
    independently compiled foreign consumer/producer execution.

COM INTERFACE EXPOSURE is distinct from COM CLASS ACTIVATION.

    [Shared, COMExport]
        may expose a returned/factory-created interface in-process without
        registering a creatable Windows class.

    [COMExport(clsid = CLSID_ImageProcessor, ...)]
        may request class factory/activation support as an additional,
        separately qualified option.

COM aggregation, IClassFactory, registered server activation, connection
points, type-library/IDL import/export, WinRT/IInspectable, out-of-process
marshalling and cross-apartment marshaling remain individually scoped
capabilities; do not claim them from a functioning IUnknown vtable alone.
Prefer IDL/type-library or verified declarations for import when possible.

A COM apartment model is NOT equivalent to [Monitor]. An object may be
synchronized yet prohibited from being used through an un-marshaled pointer
on another COM apartment. COM threading policy, agility and marshaling must
be separately modeled and enforced. A COM ABI adapter may supply its own
lifetime state as long as it preserves native [Shared] semantics and the
foreign reference obligations without double release or identity drift.

COM should ultimately make consumption of DirectX-style APIs convenient
without requiring hand-coded C++ IUnknown boilerplate. Native Astra source
should remain readable, and platform-specific costs must be explicit.


======================================================================
75. GOBJECT IMPORT, EXPORT AND SHARED LIFETIME TRANSLATION
======================================================================

AGREED DIRECTION: attributes such as [GObjectImport] and [GObjectExport]
should express deliberate GObject/GIR boundaries. The conceptual form

    [Shared, GObjectExport]
    class ApplicationSettings { }

means the exported FOREIGN view obeys GObject lifetime semantics, including
appropriate g_object_ref()/g_object_unref(), GType registration, properties,
signals, weak access and finalization behavior in its qualified domain.

It does NOT mean all native Astra objects become GObjects, nor that the
native ApplicationSettings allocation must physically inherit GObject's
layout. Native representations remain compiler-owned. A generated wrapper,
adapter or bridge can implement the foreign physical representation.

The difficult contract is identity and lifetime translation:

    repeated native-to-GObject and GObject-to-native conversion;
    uniqueness/stability of the relevant adapter identity;
    prevention of premature native or foreign destruction;
    control of native/GObject strong/weak relationships and reference cycles;
    foreign callback and signal retention/disconnection/quiescence;
    thread ownership and object-affinity rules;
    typed property and error marshaling;
    optional introspection data: GIR, typelib and metadata.

GInitiallyUnowned floating-reference conventions apply when the specific
exported base/interface requires them, not automatically to every GObject.
The precise wrapper architecture and handling of cases where native and
foreign reference counts coexist remain OPEN and require proof before use.

COM and GObject may be exported from the SAME native type through distinct
adapters, but independent foreign pointer identities MUST map consistently
to the intended native instance; one foreign reference system must not
silently own or destroy the other's state.

GObject is permanently optional. An application not using the adapter must
not acquire a mandatory GLib/GObject dependency.


======================================================================
76. LAZY CACHING, TRACKING, OBSERVATION AND MEMOIZATION
======================================================================

AGREED DESIGN SEPARATION: do not conflate simple [Lazy] caching with a
reactive, invalidating dependency graph.

    [Lazy]
    property Histogram histogram { get { return compute_histogram(); } }

This sketch implies first-success initialization and subsequent cached
observations according to the property's owning/borrowed value contract.
Failure, recursion, cancellation, destruction and reentrancy must remain
explicit. Historical accepted Astra lazy-property syntax is not removed or
silently changed by introducing an attribute spelling.

RECOMMENDED DISTINCT CAPABILITIES:

    [Tracked]
        derive or declare dependencies and invalidate/recompute a cached
        property when relevant state changes. Dependencies, side effects,
        dynamic edges, cycles and replacement lifetimes need a contract.

    [Observable]
        permit change subscriptions with explicit notification, ordering,
        retained-callback lifetime and disconnection behavior.

    [Memoized]
        cache suitable function results keyed by defined equality/hash,
        with storage, eviction, side-effect and invalidation policies.

    [Lazy]
        initialize on the first suitable access; do not silently track
        dependencies or invalidate when arbitrary fields change.

A compiler-aware property graph should preserve property identity until the
optimizer can reason about direct loading, inlining, cache elimination and
safe invalidation. It is not merely an opaque library wrapper or a promise
of hidden refresh behavior.

[Tracked], [Observable] and [Memoized] remain CANDIDATES pending concrete
requirements, cost/consistency budgets and an independent implementation
decision. In particular, dependency observation must never allow a callback
to witness a partially constructed owning cache or outlive its receiver.


======================================================================
77. ADDITIONAL ATTRIBUTE CANDIDATES AND SAFETY REQUIREMENTS
======================================================================

The following are CANDIDATES / RECOMMENDED DESIGN options, not approved
implemented syntax. Their design is subject to evidence and compatibility.

    [Reflect]
        opt in to suitable runtime metadata and inspection. No all-Class
        heavyweight RTTI tax or automatic GObject identity.

    [Derive(Eq, Hash, Debug)]
        generate compiler-checked operations only when member semantics,
        ownership and costs are valid. Unavailable derivations reject.

    [NoEscape]
        describe a proven call/foreign callback nonretention contract.
        A foreign declaration cannot become safe merely by making a claim.

    [ThreadBound]
        enforce one thread/executor affinity and reject inappropriate
        transfer and access, including through closures/adapters.

    [Repr(C)]
        explicit C-compatible value layout where achievable, independently
        verified against the relevant target ABI; not a GObject/COM Class
        representation shortcut.

    [Align(32)]
        explicit storage/alignment requirement, with overflow/layout and
        allocator checks; no universal performance guarantee.

    [Allocator(...)]
        type- or abstraction-level allocation authority with lifetime,
        alignment, failure and region-escape contracts. Must compose with
        constructor/destructor and freestanding semantics.

    [MustUse]
        diagnose discarded owning values, checked errors or important
        results under a clear effect contract.

    [Pure]
        checked side-effect promise with well-defined reads, allocation,
        exceptions and foreign-call policy; never blindly trust it for
        optimizer-eliminated effects.

    [Interrupt]
        controlled hardware interrupt entry restrictions, target ABI and
        concurrency constraints; qualify on actual embedded targets.

    [Deprecated]
        user-facing diagnostics with version/migration metadata.

    [Actor]
        optional executor-serialized concurrency model, distinct from
        method-level [Monitor] locking.

    [Agile] / [COMExport(threading = ...)]
        a qualified COM threading/apartment policy; not permission to
        skip required COM marshaling.

Candidate policy names should be namespaced or otherwise resolved without
confusing user-defined identifiers, foreign metadata and built-in semantics.
Existing [ExceptionRoot] and other current compiler-recognized attributes
remain subject to their already qualified meanings.


======================================================================
78. COMPILER ARCHITECTURE, INTROSPECTION AND PROOF OBLIGATIONS
======================================================================

RECOMMENDED IMPLEMENTATION APPROACH:

    source declaration + parsed attribute arguments
        -> canonical typed policy identities
        -> applicability and combination analysis
        -> checked semantic model and effect/ownership contracts
        -> Core IR / CFG / SSA / lifetime and layout authority
        -> target/native or explicit foreign ABI adapter
        -> LLVM IR / runtime pieces strictly when required

Do not implement [Shared], [Monitor], [Lazy] and COM/GObject export as
independent uncoordinated source-to-source transforms. Semantic ownership,
identity, storage and effect rules must have ONE authoritative interpretation
used by native code and by every foreign adapter.

Required negative/positive proof classes include:

    attribute placement, wrong argument type, duplicate/conflicting policies;
    correct policy on inherited Classes, generic specializations and modules;
    double release, use after move, borrowed escape, weak upgrade after death;
    missed lock release, protected-state escape, lock/await conflict;
    singleton recursion, failed init, teardown and attempted second instance;
    lazy reentrancy/failure, graph cycles and invalidation ownership;
    foreign interface pointer and reference identity across ABI boundaries;
    invalid calling convention / ABI / IID / GUID / HRESULT mapping;
    optional runtime dependencies not linked when unused;
    IR-corruption tests that provoke explicit verifier failure;
    actual native, independently optimized and foreign-client execution.

Compiler metadata should permit human-readable inspection of the derived
policy and material costs. A possible tool is:

    astrac --explain-semantics Registry

which could describe ownership, synchronization, initialization, allocation,
reflection/export adapters and runtime dependencies. The exact CLI syntax is
a CANDIDATE. Such inspection is especially valuable when reviewing
AI-produced source code containing compact attribute lists.

Policy implementations must avoid hiding large costs or risks behind a
one-word annotation. The user should be able to discover allocations,
refcounts, locks, metadata, blocking effects, thread restrictions and
foreign ABI dependencies from compiler diagnostics or introspection.


======================================================================
79. COMPOSITION, CONFLICT RULES AND COST VISIBILITY
======================================================================

AGREED DIRECTION: meaningful cross-policy combinations must be supported
when their contracts can be made consistent. Example:

    [Shared, Monitor, Singleton]
    class Registry { }

The following semantic dimensions remain distinct:

    instance construction/location       Singleton
    default ownership and representation Shared
    synchronization of mutable state     Monitor
    foreign interface/lifetime ABI       COMExport / CExport / GObjectExport
    optional metadata                   Reflect
    computation and cache state         Lazy / Tracked / Observable

An attribute list is not a sequence of unchecked rewrites. The compiler
must derive one coherent aggregate contract, report its costs and reject
incompatible combinations.

Example policy constraints to qualify rather than assume:

    [Shared] with [Singleton]
        define the singleton strong anchor, whether shutdown permits weak
        upgrades, and when the unique instance can be destroyed.

    [Shared] with [Monitor]
        enforce method synchronization separately from reference-counter
        safety; no automatic proof of deadlock freedom.

    [Monitor] with async methods
        prohibit unqualified suspension under lock or provide a separate
        explicit, tested async state/lock protocol.

    [Shared, COMExport, GObjectExport]
        native instance stays logically identifiable through COM's
        IUnknown and GObject's GType/reference worlds. Each adapter must
        satisfy its own ABI, with explicit lifetime translation.

    [CExport, COMExport]
        C uses the declared C boundary; COM supplies independent vtables
        and QueryInterface. Exporting through one does not imply the other.

    [Repr(C)] with native Class
        do not promise a general C struct ABI for a native identity object.

    [Lazy, Tracked]
        requires an explicitly approved invalidation/lifetime model;
        treating the words as independent may lead to stale borrowed data.

    [ThreadBound] with [COMExport(threading = Agile)]
        reject unless the declared apartment/transfer semantics are
        genuinely compatible.

No attribute combination is permitted to weaken an existing verified
ownership, ABI or effect contract merely to enable a convenient spelling.


======================================================================
80. ADOPTION ROADMAP AND REAL QUALIFICATION
======================================================================

This amendment is written while ASTRA-LANGUAGE-GENERALIZATION-SURGE-10 is
already submitted. Do NOT edit that task's frozen scope or start modifying
a live checkout solely because this design addendum exists.

The negotiated major plan remains Surges 10-14, with COM support added to
the foreign-interop work and a shared attribute/policy infrastructure
coordinating the required language semantics.

    Surge 10 — Language generalization
        retain already submitted scope. Review any policy/attribute
        infrastructure already present; do not infer new [Shared], COM,
        Monitor, Actor or graph attributes are delivered.

    Surge 11 — Numerics and optimization
        investigate checked [Pure], [Align], allocation/alias policy
        metadata and composable FP semantics without blind optimizer
        promises or syntax drift.

    Surge 12 — Freestanding and allocation
        investigate [Allocator], [Repr(C)] and target/hardware-facing
        policies. Qualify actual no-OS execution on a selected non-SH-4
        target, independent of optional GObject/COM services.

    Surge 13 — Concurrency and runtime
        implement/test the necessary thread, atomic shared/weak, monitor,
        synchronization and executor contracts; consider [ThreadBound],
        [Singleton] and [Actor] under explicit gates.

    Surge 14 — Interoperability, tooling and release
        coordinate [Shared]/'shared T' semantics, [CImport]/[CExport],
        [COMImport]/[COMExport], [GObjectImport]/[GObjectExport], opt-in
        metadata, complete ABI adapters, package/language tooling and a
        fresh full release integration/conformance campaign.

The above is a DESIGN/PLANNING SUGGESTION, not automatic execution authority.
COM import/export is NEW scope beyond the previously frozen Surge 14 plan;
its scheduling, target host, selected interface profile, and priority must be
explicitly authorized in a future submission. Native Windows/COM target
qualification may require an available Windows execution environment; a
Linux-produced file or source-level layout check alone is insufficient.

At every adoption step:

    preserve historical accepted capabilities and negative controls;
    qualify every source-to-ABI lifetime/identity change independently;
    keep liburing/Linux, GObject/GLib, Windows/COM, and freestanding runtime
        dependencies separately optional and explicit;
    do not invent a PASS for absent host or hardware execution;
    keep source changes and test evidence Git-pinned and reviewable;
    continue the finish-or-resume workflow within real session/safety limits.

SH-4/Dreamcast support and Stage-1/Stage-2 self-hosting remain DEFERRED by
separate user decisions. This amendment does not revive either as a surge
gate. Real non-SH-4 freestanding qualification remains in scope.


======================================================================
81. OPEN DESIGN QUESTIONS — ATTRIBUTE/INTEROPERABILITY REGISTER
======================================================================

Preserve these unresolved questions as distinct design inputs; an example
using one possible spelling does not close a question.

    ATTR-01  Exact attribute grammar, namespacing and typed arguments.
    ATTR-02  Built-in versus ordinary metadata/user attributes; inheritance.
    ATTR-03  Commutativity, conflicts, versioning and library ABI contracts.

    SHARE-01 Automatic retain-on-copy versus explicit clone/retain.
    SHARE-02 Weak-control anchor placement, cleanup order and cycles.
    SHARE-03 Shared Class transfer/thread safety and allocation policy.
    SHARE-04 Whether shared [Shared] T spelling is invalid or meaningful.
    SHARE-05 Existing Shared<T>/Weak<T> migration and compatibility.

    MON-01  [Mutex] alias versus [Monitor] spelling.
    MON-02  Monitor reentrancy, nested lock order and exception safety.
    MON-03  Callback, property and await restrictions under lock.
    ACT-01  Actor executor, mailbox, cancellation and ownership model.

    SING-01 Scope, eager/lazy init, failure, recursion and destruction.
    SING-02 Shared singleton strong anchor and shutdown/weak semantics.

    CABI-01 Exact CImport/CExport syntax and stable interface guarantees.
    CABI-02 Ownership, pointer/record/return/error and callback mapping.

    COM-01  First supported Windows target and platform calling convention.
    COM-02  IID/CLSID/IDL/typelib import and versioning authority.
    COM-03  IUnknown identity across interfaces and native wrappers.
    COM-04  HRESULT/success-status/throws/out-parameter mapping.
    COM-05  Export versus class activation/aggregation/server support.
    COM-06  Apartments, agility, marshaling and threading compatibility.

    GOBJ-01 Wrapper uniqueness, dual retention and reference cycles.
    GOBJ-02 GType/GIR/typelib export, properties and signal lifetimes.
    GOBJ-03 GInitiallyUnowned floating references and thread affinity.
    GOBJ-04 Combined COM/GObject/C exports of one native instance.

    PROP-01 [Lazy] sugar versus canonical lazy-property declaration syntax.
    PROP-02 [Tracked] dynamic/static dependencies, cycles and invalidation.
    PROP-03 [Observable] callbacks, notification and owner lifetimes.
    PROP-04 [Memoized] keys, eviction, effects and storage authority.

    META-01 [Reflect], [Derive], [Pure] and compiler policy inspection.
    META-02 [NoEscape], [Interrupt] and foreign trust/target proofs.

Every closure decision must record rationale, changes to existing syntax,
ABI and lifetime contracts, negative tests, runtime requirements and
compatibility impact. Keep this register as a bridge to actual ADRs and
engineering submissions, not a substitute for them.


======================================================================
82. DESIGN SKETCH: ONE NATIVE TYPE, MULTIPLE FOREIGN PERSONALITIES
======================================================================

The long-term composition we want to investigate is:

    [Shared, Monitor, Singleton,
     CExport, COMExport, GObjectExport]
    class Registry : IRegistry {
        // Native Astra implementation
    }

The native Class owns its semantic identity and lifecycle policy.

    native Astra access
        uses the declared intrusive sharing/monitor/singleton contracts;

    C ABI access
        uses generated opaque retain/release and typed API operations;

    COM ABI access
        uses IID/vtables/IUnknown identity, HRESULT and reference rules;

    GObject ABI access
        uses a generated GType-aware GObject lifetime/metadata adapter.

The physical pointers need not be interchangeable. Multiple foreign wrappers
must preserve the intended native object identity, not create duplicate
native owners or competing cleanup authorities. Callback, weak-reference,
shutdown, locking and threading contracts must remain coherent across the
three worlds.

This composition is a RESEARCH AND IMPLEMENTATION GOAL, not a claim that
combining these six attributes is legal or safe in today's compiler.

Founding standard reaffirmed:

    MAKE SOPHISTICATED SYSTEMS PROGRAMMING LOOK ORDINARY.

    DECLARE POLICY ONCE; KEEP THE COSTS AND CONTRACTS VISIBLE.

    NATIVE FIRST. COMPATIBILITY AT THE BOUNDARY.

Made by Ria and Pim. 💙🖤
