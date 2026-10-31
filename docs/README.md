# Astra documentation

The complete Astra compiler is the preserved Vala implementation in `bootstrap/`.
The self-hosting transition will introduce Astra compiler components separately.

Start with [build and test instructions](toolchain.md), the
[language syntax](language/syntax.md), [capability matrix](language/capabilities.md)
and [example tour](../examples/README.md). Current library, ownership and foreign
contracts are documented under `language/`, `library/`, `abi/` and `vapi/`.
The [architecture](architecture/overview.md), [invariants](architecture/invariants.md)
and numbered [decisions](decisions/0001-license.md) explain the independent
verification boundaries. An early decision records its scoped introduction;
later language guides and decisions describe extensions.

The canonical [Founding Bible](history/ASTRA_FOUNDING_BIBLE_2026-10-18.md) and
[roadmap v2](history/ASTRA_VISION_AND_ROADMAP_v2.0_2026-10-18.md) retain project
direction. The [earlier living roadmap](vision-and-roadmap.md) records its own dated
questions and amendments; its old milestone status is not a current test result.

[Source style](../CODING_STYLE.md) describes the guarded formatter and
byte-sensitive fixtures. [Packages](tools/packages.md),
[editor integration](tools/language-server.md) and
[developer distributions](tools/developer-release.md) describe optional tooling.

Historical qualifications apply only to their recorded source/compiler/profile.
Current regression execution never upgrades a failed or expired freeze.
[Git recovery](history/active-tree.md) covers retired reports and campaign tools;
[bootstrap provenance](../bootstrap/provenance.json) identifies the separate donor
archive. Detailed new execution evidence belongs outside the source tree.
