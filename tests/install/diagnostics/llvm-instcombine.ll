; LLVM-only reproducer: no Astra source, adapter, target or runtime.
define i32 @add(i32 %a, i32 %b) {
  %v = add i32 %a, %b
  ret i32 %v
}

define i32 @bitand(i32 %a, i32 %b) {
  %v = and i32 %a, %b
  ret i32 %v
}
