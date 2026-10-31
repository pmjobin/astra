# Error and RuntimeError

Include `lib/astra/base/errors.astra` as an ordinary source file, or use its installed `share/astra/base/errors.astra` counterpart. It declares the nominated Error root, its readonly text snapshot, the get-only virtual message property, and RuntimeError with explicit base initialization. No formatting or outcome API is involved.

Constructors take a string borrow and snapshot its exact bytes. The immutable snapshot survives the input producer. Derive application exceptions normally and catch them through Error. The installed four-source fixture combines this library, hosted/text.astra and two application files; it uses the existing println provider and checks all 24 source orders.

The library is opt-in source. A user root and this library root cannot be nominated together. Application code selects failure/status adaptation explicitly. No executor, provider registration, cancellation exception or implicit C unwind is supplied.
