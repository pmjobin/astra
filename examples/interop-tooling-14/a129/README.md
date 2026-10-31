# A129 packaged diagnostic transformer

The independent consumer imports the installed versioned `transform14@0.9.0`,
which depends on `records14@0.2.1` and `foundation14@0.4.0`. The recipe copies the
explicit library sources and separately compiled POSIX objects into those
packages, locks/installs them, withholds their producer paths and moves the
package installation. Consumer builds then use only that offline prefix and
their existing path-independent integrity lock.

Input lines have `0|payload`, `1|payload` or `2|payload` form. The transformer
validates UTF-8, coalesces consecutive equal records into owned generic runs,
preserves counted Unicode/NUL payload bytes, and writes severity totals. Empty
lines, CRLF and a final line without newline are handled explicitly. Invalid
record/UTF-8 input returns 3; file failures return 2; missing arguments return 64.
Output is created only after successful parsing/rendering.

Run `python3 tests/interop-tooling-14/a129-packaged-transformer.py ASTRAC EXTERNAL_OUTPUT`.
Add `--prefix INSTALLED_PREFIX` to use an independently installed compiler,
`astra-pkg`, library/providers and sample sources. The development recipe passes
O0/O1/O2 against exact independent Python byte oracles, including random records,
Unicode, embedded NUL, empty/repeated input and error cleanup. O0/O2 successful
and failing cases pass unsuppressed Valgrind with every leak kind an error.
Dependency tampering refuses before code generation; restored bytes permit
execution with the original unchanged lock. Final release-prefix qualification
remains separate from a development compiler run.
