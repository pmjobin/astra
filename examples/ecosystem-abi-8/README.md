> Historical donor documentation, preserved for design and usage context. Private host paths are omitted; original bytes and qualification receipts remain in the verified donor archive. This is not current foundation qualification.

# A57–A64 — ecosystem/native/debug applications

These eight distinct Astra programs use the public driver and explicit optional
providers. Each A57…A64 directory has a scenario README; sources live here.
Run the single reproducible qualification recipe from the coordinator:

```sh
python3 tests/ecosystem-abi-8/apps-check.py \
  <historical-private-path> \
  <historical-private-path>
```

The recipe is an ordinary foreground test, not a build coordinator. It selects
installed `pkg-config --cflags/--libs gobject-2.0`, compiles named optional C
providers with Clang `-std=c11 -g -gdwarf-4 -O2 -Wall -Wextra -Werror`, imports
installed GObject GIR and the maintained fixture via `tools/gir/import.py`, and
verifies all generated outputs before use. No generated declarations live in
Git. The native producers run separately at O0 and O2 with explicit exported
names. Consumers receive the interface plus their own source and selected
stdlib files; existing producer objects are supplied only to the later linker.

Every consumer uses `astrac -g -O0/-O2 --entry-object`, `common.astra`,
`base/errors.astra`, `hosted/text.astra`, `hosted/files.astra`,
`text/utf8-message.astra`, `text/utf8-byte-builder.astra`, and
`text/scalar-format.astra`. Foreign apps select the maintained VAPI or generated
GIR declarations. A57/A58 add `foreign-text.astra`; A59/A63 add
`record-log.astra` and the signal VAPI. A61–A63 import Work8; A64 imports
Analyzer8. Exact commands are retained individually in the JSON receipt.

All apps link explicit text, text-ops, files, argv and observation C providers.
Only A57/A58/A59/A60/A63 link optional GObject providers and real GObject/GLib.
A61/A62/A64 have no GObject dependency. A60 writes `gir-report.txt`; A64 reads
`abc 12\n\tXYZ9\n` and writes `analysis.txt`. Other apps have no input files.
O1 spots cover the signal recorder and source analyzer. Each O0/O2 executable
runs under unsuppressed Valgrind; definite, indirect and possible losses must
all be zero. GLib reachable bytes are recorded separately in each raw log.
Clang ASan/UBSan instrument explicit C boundaries and allocation interceptors
for A62/A63; Astra LLVM instructions and system GLib are not instrumented.
DWARF verification, GDB and formatted independent A64 modules exercise source
identity. The separate debug/module mutation proofs cover corrupt/restored
backend metadata. These apps extend historical A01–A56 without claiming those
56 have all been rerun.
