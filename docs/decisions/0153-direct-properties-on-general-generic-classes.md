# Direct properties on general generic Classes

General-body generic Classes can declare direct, computed, get-only int and bool
properties alongside their existing one owned `T[slots]` field, constructor,
ordinary members and copied-U methods. Each closed specialization gets ordinary
typed property/getter identities and receiver authority. No getter is cached
implicitly. Generic inheritance, setters, virtual dispatch, lazy/throwing getters
on the template itself and T-valued projections remain outside this profile.
The older `where T : ExactHeapClass` Bag profile keeps its historical refusal.

The immutable generic definition snapshots property names and copied result
roles in declaration order, separately from method signatures. It rejects
duplicate/colliding names and illegal result roles. Source completes accessor
bodies under the exact specialization and normalizes member ordinals after all
closed U methods are known, preserving distinct field, lifecycle, method and
property domains even when source declarations interleave them.

Core, CFG and SSA independently compare the full property inventory with that
definition. They require the exact name, ordinal, type, direct copied getter,
receiver and program-owned function, and reject cached/borrowed/owned/setter
substitutions. Normal property and ownership verifiers still check bodies and
uses. No stage treats a generic property as permission to reinterpret element
storage or return an owned slot through a borrowed getter.

Native specialization keys snapshot the property target ordinals. The native
verifier checks each target's Class, property ordinal, accessor kind, result
channel and absence of ownership/cache/exception channels. Extra accessors and
erased or substituted target inventories reject independently of SSA. Accessor
functions keep their established `get` spelling; property names belong to the
immutable declaration schema and property ordinal rather than the function's
debug name. Default Class layout and external C ABI do not change.

The source witness declares properties before the constructor, between methods
and beside a copied generic method, and independently instantiates copied record,
unique Class and move-only Resource/buffer record elements. Observations before
and after growth and extraction prove fresh computation. Explicit owner moves,
exact copied-U results and destructor traces retain their ordinary semantics.
Public invalid forms and independently corrupted/restored Core/CFG/SSA/native
inventories and receiver bindings accompany O0/O1/O2 and memory qualification.
