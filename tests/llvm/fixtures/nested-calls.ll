; ModuleID = 'astra.scalar'
source_filename = "astra.scalar"

define internal fastcc i32 @astra.fn.0(i32 %p0) {
b0:
  ret i32 %p0
}

define internal fastcc i32 @astra.fn.1(i32 %p0, i32 %p1) {
b0:
  %v2 = add i32 %p0, %p1
  ret i32 %v2
}

define internal fastcc i32 @astra.fn.2() {
b0:
  %v0 = call fastcc i32 @astra.fn.0(i32 1)
  %v1 = call fastcc i32 @astra.fn.0(i32 2)
  %v2 = call fastcc i32 @astra.fn.1(i32 %v0, i32 %v1)
  ret i32 %v2
}
