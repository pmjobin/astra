# 0081: Qualify the retained CAD application

Status: accepted qualification policy; application outcome is recorded separately.

The application authority is `aster-scale` commit
`f415381f92daecfa683838206dffa5ea78d78477`, tree
`8c677a2fa2f40ea4d2456fbcdb8d721b96be8546`. Its original independent oracle,
selected production tests, synthetic generators and local reference hashes are
part of that authority. Later PIXEL work is outside this campaign.

The compiler baseline is `4c59bf432a48bea7bf2bf262c296aa0c868ffec3`.
Compiler implementation, language contracts, libraries, providers and existing
test expectations are frozen. This decision adds no language semantics.

Qualification separates historical reconstruction L (`a1fadc5c052e82ae464268787f617252998c24be`),
compatibility port P (current compiler with the old numerical representation),
and idiomatic application I (current compiler with typed records and owned arrays).
L must reproduce its original acceptance before migration parity is claimed;
P must qualify before the data representation changes are judged.

Native route comparisons require exact corresponding state, decisions, output
samples, iterations and correction counts. The independent oracle keeps its own
original tolerances and symmetry conditions. Those tolerances cannot waive a
native port difference. Numerical algorithm changes are outside this campaign.

Inputs are resolved locally and read-only, then verified against exact Git blobs
and modes. Sources, builds and evidence live under `build/app-cad-1/`.
Reference images remain local-only. Missing exact inputs produce BLOCKED_INPUT;
reports alone cannot establish application acceptance. No network download,
package installation, expectation regeneration or compiler repair is implicit.

The validation report records the actual outcome,
including incomplete obligations. PASS requires the real application, original
acceptance, both ports, exact native parity, normal cleanup and installed execution.
Performance may regress without waiving correctness. Any next capability campaign
requires a separate decision supported by an observed application obstacle.
