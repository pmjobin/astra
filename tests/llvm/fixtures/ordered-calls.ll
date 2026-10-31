; ModuleID = 'astra.scalar'
source_filename = "astra.scalar"

define internal fastcc i32 @astra.fn.0() {
b0:
  ret i32 1
}

define internal fastcc i32 @astra.fn.1() {
b0:
  ret i32 2
}

define internal fastcc i32 @astra.fn.2() {
b0:
  %v0 = call fastcc i32 @astra.fn.0()
  %v1 = call fastcc i32 @astra.fn.1()
  %v2 = add i32 %v0, %v1
  ret i32 %v2
}
