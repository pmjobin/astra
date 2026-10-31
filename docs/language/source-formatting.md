# Formatting Astra source

```sh
astrac --format input.astra                 # stdout; source unchanged
astrac --format --check input.astra         # 0 unchanged, 1 differs/invalid
astrac --format input.astra -o new.astra     # new file; refuses overwrite
astrac --format --in-place input.astra      # explicitly replace source
astrac --format --version
```

Formatter version 1 uses real hard TAB indentation and preserves intra-line layout,
comments, literal spellings, line endings, and existing line numbers. It validates
the supported grammar before writing, then independently checks that the formatted
output has exactly the same tokens and comments. Malformed input produces the
compiler's normal line/column diagnostic without writing output.

Multi-line comments and literals keep their exact internal bytes. Leading braces
and parentheses inside comments or literals do not affect indentation. The tool
adds a final newline if missing. It does not reflow statements or align columns.

See [ADR 0123](../decisions/0123-conservative-source-formatter.md) for the contract
and qualification boundary.
