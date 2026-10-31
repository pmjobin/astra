# ADR 0001: Compiler and runtime license

Status: accepted in ASTRA-CHARTER-1.

## Decision

Use `SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception` for Astra-owned
compiler and future runtime source, unless a future exception is deliberately
reviewed. Newly authored source and build files carry that identifier.
[LICENSE.txt](../../LICENSE.txt) contains the complete Apache 2.0 text and LLVM exception.

## Rationale and consequences

Astra is intended to be permissively and commercially usable across systems
language applications. Apache 2.0 supplies an explicit contributor patent grant
and established redistribution terms. The LLVM exception is suitable for
compiler/runtime code and generated-program distribution: it relaxes specific
redistribution conditions for covered portions embedded into compiled output,
and includes the specified GPLv2 combination provision. It does not impose an
Astra runtime or determine the license of independently authored user programs.

The authoritative identifiers and terms are [Apache-2.0](https://spdx.org/licenses/Apache-2.0.html)
and [LLVM-exception](https://spdx.org/licenses/LLVM-exception.html). The legal text
was taken from the system LLVM 22.1.8 package's license, containing those terms;
LLVM's project-specific third-party and legacy license sections were not adopted.
No LLVM implementation source was copied.

License compatibility does not establish provenance or architectural authority.
Vala and frozen LLVM-v2 implementation source remains excluded independently of
its license. Future external source requires an explicit provenance/license review.
