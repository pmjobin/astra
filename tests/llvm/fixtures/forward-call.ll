; ModuleID = 'astra.scalar'
source_filename = "astra.scalar"

define internal fastcc i32 @astra.fn.0(i32 %p0) {
b0:
  %v1 = call fastcc i32 @astra.fn.1(i32 %p0)
  ret i32 %v1
}

define internal fastcc i32 @astra.fn.1(i32 %p0) {
b0:
  %v1 = add i32 %p0, 1
  ret i32 %v1
}
