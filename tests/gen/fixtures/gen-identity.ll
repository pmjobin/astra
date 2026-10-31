; ModuleID = 'astra.scalar'
source_filename = "astra.scalar"

define internal fastcc i32 @astra.fn.0() {
b0:
  %v0 = call fastcc i32 @astra.fn.1(i32 42)
  ret i32 %v0
}

define internal fastcc i32 @astra.fn.1(i32 %p0) {
b0:
  ret i32 %p0
}
