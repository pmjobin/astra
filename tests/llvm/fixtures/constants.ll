; ModuleID = 'astra.scalar'
source_filename = "astra.scalar"

define internal fastcc i32 @astra.fn.0() {
b0:
  ret i32 0
}

define internal fastcc i32 @astra.fn.1() {
b0:
  ret i32 2147483647
}

define internal fastcc i32 @astra.fn.2() {
b0:
  ret i32 -1
}

define internal fastcc i32 @astra.fn.3() {
b0:
  ret i32 -2147483648
}

define internal fastcc i1 @astra.fn.4() {
b0:
  ret i1 true
}

define internal fastcc i1 @astra.fn.5() {
b0:
  ret i1 false
}

define internal fastcc void @astra.fn.6() {
b0:
  ret void
}

define internal fastcc void @astra.fn.7() {
b0:
  ret void
}
