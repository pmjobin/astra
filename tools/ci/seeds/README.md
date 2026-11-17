# Public CI bootstrap input

The owner explicitly approved public distribution of this exact Astra ELF on
2026-11-17. It is 2,388,496 bytes, SHA-256
`560e7c9eaeb6cdb974efdd43ed4ac41191cdda4acdb4afd77052325addf1f1c6`. `PROVENANCE.json` binds its already-public source, generation recipe and historical qualification. The full source license is preserved in `LICENSE.txt`.

This is the frozen 27-D Stage3 O2 compiler produced by Stage2 O2. It is a
bootstrap input, not a new compiler generation or an installer. Linux x86-64
and the separately acquired exact LLVM 23.1.4 C API / GNU C library are required.
LLVM and glibc libraries are dynamically linked and are not bundled here; their
separate distributions retain their own license notices.

The exact ELF retains public-project source paths in diagnostic strings. The
static credential-pattern scan found no matches, and embedded home paths were
checked against public source. No C0 oracle, private qualification inputs,
installer or report archive is included. Original LLVM and rebuilt-C0 memory
NOT_PASS, missing original C0/1,044 proofs, formal Reference PARTIAL and Windows
unqualified status remain unchanged.

CI acquisition uses an immutable raw Git commit URL and independently checks
the byte count and SHA-256 in `../seed-linux.json`. CI artifact retention is not
the seed distribution mechanism. No GitHub Release is created.
