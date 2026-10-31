# Recovering retired reports and campaign tools

Cleanup 3 retires obsolete reports, registries, source inventories, completed
proposals and their campaign-only readers from the active checkout. Their exact
bytes and modes remain in Git at `1ed7c322befe662e7051f42a58b596d221477f9c`:

```sh
git show 1ed7c322befe662e7051f42a58b596d221477f9c:PATH > /external/recovered-file
git ls-tree 1ed7c322befe662e7051f42a58b596d221477f9c -- PATH
```

The six tables retired by Lexer 2 remain at
`06f766712f9df704acc7fb2eb652f286771214b5`. Bootstrap relocation is recorded in
[relocation.json](../../bootstrap/relocation.json). External archives, previous
reports, donor sources and prior build products are preserved separately.

Historical outcomes keep their original scope. In particular, runtime-composition
freezes 1 and 2 failed; freeze 3's scoped B3 execution passed and then expired after
the independent ABI-isolation failure and repair. Repaired current regressions do
not retroactively qualify those freezes. Earlier accepted, rejected, pending and
expired milestone records remain recoverable without changing their verdicts.
Current rules live in the language/IR/ABI/architecture references and actual tests;
old no-feature restrictions and fixed registration counts are not current rules.

The Cleanup 3 report carries the complete disposition/coverage mapping, inventory,
source-bound patch and measured evidence. No per-file archive copy is maintained
in this checkout. Detailed future execution receipts belong outside Git.
