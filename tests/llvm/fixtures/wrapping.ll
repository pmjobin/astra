; ModuleID = 'astra.scalar'
source_filename = "astra.scalar"

define internal fastcc i32 @astra.fn.0(i32 %p0, i32 %p1) {
b0:
  %v2 = add i32 %p0, %p1
  ret i32 %v2
}

define internal fastcc i32 @astra.fn.1(i32 %p0, i32 %p1) {
b0:
  %v2 = sub i32 %p0, %p1
  ret i32 %v2
}

define internal fastcc i32 @astra.fn.2(i32 %p0, i32 %p1) {
b0:
  %v2 = mul i32 %p0, %p1
  ret i32 %v2
}

define internal fastcc i32 @astra.fn.3(i32 %p0) {
b0:
  %v1 = sub i32 0, %p0
  ret i32 %v1
}

define internal fastcc i32 @astra.fn.4(i32 %p0) {
b0:
  ret i32 %p0
}

define internal fastcc i32 @astra.fn.5() {
b0:
  ret i32 -2147483648
}

define internal fastcc i32 @astra.fn.6() {
b0:
  ret i32 2147483647
}

define internal fastcc i32 @astra.fn.7() {
b0:
  ret i32 -2
}

define internal fastcc i32 @astra.fn.8() {
b0:
  ret i32 -2147483648
}
