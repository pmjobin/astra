# Preserved Vala implementation

The subsystem directories here contain the complete compiler implementation, including the
module-owned LLVM layout-cache lifetime repair. Build the root Meson `astrac`
target to produce the development seed (C0). No donor checkout or old build
directory is an input to that build.

C0 is a repaired development compiler. The historical RC2 binary predates the
layout repair and is not interchangeable with it. C1/C2/C3 equivalence remains
future work; a compiled source component is not a complete self-hosted compiler.
