# Native classes

A plain Class parameter is a nullable bounded borrow of the existing
ObjectStorage. Mutation through that reference remains visible and two borrowed
parameters may alias. Native constructors may temporarily use plain Class,
Resource and Slice inputs, but persistent owned Resource/buffer fields require
explicit `owned` inputs and transfer. See [parameter borrowing](parameter-borrowing.md).

BUFFER-1 extends ownership-bearing classes with `owned T[]` fields for admitted
[buffer elements](owned-runtime-arrays.md). Explicit constructors initialize each
field exactly once from `new T[count]`, moved named owners or exact factory
results. Methods and scalar accessors may borrow, index, inspect `len`, or replace
fields. Resource and buffer fields share reverse declaration cleanup after normal
deinit; deinit may replace current contents. Object aliases observe replacement.
No owned-buffer property, field move-out, field release or new object ABI is added.

Native class identity, layout and members follow the [object model](objects.md),
[lifecycle rules](object-lifecycle.md), [object ownership](object-ownership.md)
and [object results](object-results.md).

OWN-FIELD-1 additionally supports explicit `owned ResourceType field;` with exact
nominal Resource type and cleanup authority. An explicit constructor initializes
every field exactly once. Temporary use borrows, replacement acquires the incoming
owner before releasing the old one, and normal destruction releases final field
contents after user deinit in reverse declaration order. Replacement is legal
inside deinit and through its methods or setters. Concrete null is an initialized
owner requiring no release call or runtime active bit.

Plain Resource fields, owned class/struct fields, scalar/vector owner fields,
owned fields in structs, generic owner fields, move-out and explicit field
release remain excluded. Resource fields themselves require no heap. Buffer
allocation uses its qualified backend; neither domain introduces an ownership
header, destructor pointer, runtime ownership table or new class ABI. See the full
[owned Resource field rules](owned-resource-fields.md).

## Multi-source composition

A class has one declaration in the global [source program](source-files.md).
Callers in other files use its exact methods, properties, constructor and destructor.
Plain Class parameters keep PARAM-BORROW-1 borrowing; owned/move transfers and
caller-provided ObjectStorage preserve identity and cleanup across files. Types
cannot be reopened, extended or partitioned into partial declarations.

ERROR-1-R1 adds [bounded heap factories and owned heap parameters](exceptions.md)
using the same class machinery. Heap results and transfers preserve the full
dynamic object; legacy lexical/caller-backed results keep their storage contract.
Readonly string getters support local receiver views with exact owner and scope
loans. Neither a view copy nor a heap upcast creates a new allocation.
