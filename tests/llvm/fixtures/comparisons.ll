; ModuleID = 'astra.scalar'
source_filename = "astra.scalar"

define internal fastcc i1 @astra.fn.0(i32 %p0, i32 %p1) {
b0:
  %v2 = icmp slt i32 %p0, %p1
  ret i1 %v2
}

define internal fastcc i1 @astra.fn.1(i32 %p0, i32 %p1) {
b0:
  %v2 = icmp sle i32 %p0, %p1
  ret i1 %v2
}

define internal fastcc i1 @astra.fn.2(i32 %p0, i32 %p1) {
b0:
  %v2 = icmp sgt i32 %p0, %p1
  ret i1 %v2
}

define internal fastcc i1 @astra.fn.3(i32 %p0, i32 %p1) {
b0:
  %v2 = icmp sge i32 %p0, %p1
  ret i1 %v2
}

define internal fastcc i1 @astra.fn.4(i32 %p0, i32 %p1) {
b0:
  %v2 = icmp eq i32 %p0, %p1
  ret i1 %v2
}

define internal fastcc i1 @astra.fn.5(i32 %p0, i32 %p1) {
b0:
  %v2 = icmp ne i32 %p0, %p1
  ret i1 %v2
}

define internal fastcc i1 @astra.fn.6(i1 %p0, i1 %p1) {
b0:
  %v2 = icmp eq i1 %p0, %p1
  ret i1 %v2
}

define internal fastcc i1 @astra.fn.7(i1 %p0, i1 %p1) {
b0:
  %v2 = icmp ne i1 %p0, %p1
  ret i1 %v2
}

define internal fastcc i1 @astra.fn.8(i1 %p0) {
b0:
  %v1 = xor i1 %p0, true
  ret i1 %v1
}
