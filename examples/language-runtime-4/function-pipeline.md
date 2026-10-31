# A28 — first-class invoice processing pipeline

`function-pipeline.astra` selects two named native rules from runtime command-line input: unit pricing and record eligibility. `Fn<int,int>` pricing values cross result, local-copy and parameter boundaries; `Fn<bool,int>` filters records and `Fn<i64,i64>` computes the audit checksum. No nominal `invoke` wrapper or captured environment is involved.

The arguments are `MODE COUNT`. Mode 0 includes every record with retail pricing, `3 * units + 1`. Mode 1 skips every fifth record and applies wholesale pricing, `2 * units + 7`. Record `r` has `(r * 7) % 13 + 1` units. Counts 0 through 10000 are accepted. The output is runtime-generated owned UTF-8 and has three exact newline-terminated rows. For `1 7`:

```text
records=6
subtotal=116
checksum=117061
```

Empty input (`0 0` or `1 0`) produces `records=0`, `subtotal=0`, and `checksum=17`. Missing arguments, invalid mode and out-of-range count exit 64 with no output. Invalid decimal input exits 2 with no output. Valid runs exit 0.

From the repository root, run the qualification with the external compiler and scratch paths:

```sh
python3 tests/language-runtime-4/callable-check.py \
  "$HOME/Workspace/codex/work/astra/build/astrac" \
  "$HOME/Workspace/codex/work/astra/runtime/native-current/callable-tests"
```

The script records complete public `astrac -O0/-O1/-O2` commands, source and product hashes, exits and byte-exact output. It also reverses source order and executes empty, nonempty and parse-failure cases under unsuppressed Valgrind. Separate scalar ABI fixtures exercise `astrac -c` with independent GCC/Clang clients and an allocation observer for noncapturing function values. These receipts qualify this bounded application and do not establish owned-closure or Shared/Weak behavior.
