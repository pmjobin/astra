# A31 — synchronous C event bridge

`sync-event-bridge.astra FIRST COUNT MODE` runs a C event provider through the established named, synchronous, nonretaining callback ABI. The provider invokes `accept_event` in ascending input order and checks each returned sequence number against the native record's updated count. The callback selects an actual `Fn<int,int>` at runtime: mode 0 doubles the input; mode 1 adds three. The context is an exact natural LP64 POD pointer; no function value or retained environment crosses into C.

`FIRST` must be in -1000 through 1000, `COUNT` in 0 through 1000, and `MODE` either 0 or 1. For `7 5 0`, exit 0 and exact output are:

```text
events=5 checksum=90
```

For `0 0 0`, the exact output is `events=0 checksum=0` followed by a newline. Invalid numbers exit 2; missing arguments and out-of-range values exit 64, with no output. Provider protocol failure exits 3. Output failure exits 4.

Run the reproducible qualification from the repository root:

```sh
python3 tests/language-runtime-4/event-check.py \
  "$HOME/Workspace/codex/work/astra/build/astrac" \
  "$HOME/Workspace/codex/work/astra/runtime/native-current/event-tests"
```

The runner builds C providers with GCC and Clang, executes public native O0/O1/O2 CLI products, and independently links each public `astrac -c` API object to a C client. The client verifies 1400 distinct callback sequences, including empty sequences, against its own checksum oracle. The provider checks order and return values on every callback. The receipts record source/compiler/product hashes, tool versions, commands, exits, exact output and unsuppressed Valgrind results. The C provider's nonretention promise remains an explicit trusted boundary.
