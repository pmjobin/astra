; ModuleID = 'astra.scalar'
source_filename = "astra.scalar"

define internal fastcc i32 @astra.fn.0(i32 %p0) {
b0:
  ret i32 %p0
}

define internal fastcc i32 @astra.fn.1(i32 %p0) {
b0:
  ret i32 %p0
}

define internal fastcc i32 @astra.fn.2(i32 %p0) {
b0:
  ret i32 %p0
}

define internal fastcc i32 @astra.fn.3(i32 %p0, i32 %p1) {
b0:
  %v2 = call fastcc i32 @astra.fn.0(i32 %p0)
  %v3 = call fastcc i32 @astra.fn.1(i32 %p0)
  %v4.zero = icmp eq i32 %p1, 0
  br i1 %v4.zero, label %v4.trap, label %v4.nonzero

v4.trap:                                          ; preds = %b0
  call void @llvm.trap()
  unreachable

v4.nonzero:                                       ; preds = %b0
  %v4.minimum = icmp eq i32 %v3, -2147483648
  %v4.minusone = icmp eq i32 %p1, -1
  %v4.overflow = and i1 %v4.minimum, %v4.minusone
  br i1 %v4.overflow, label %v4.special, label %v4.normal

v4.special:                                       ; preds = %v4.nonzero
  br label %v4.continue

v4.normal:                                        ; preds = %v4.nonzero
  %v4.raw = sdiv i32 %v3, %p1
  br label %v4.continue

v4.continue:                                      ; preds = %v4.normal, %v4.special
  %v4 = phi i32 [ -2147483648, %v4.special ], [ %v4.raw, %v4.normal ]
  %v5 = add i32 %v2, %v4
  %v6 = call fastcc i32 @astra.fn.2(i32 %p0)
  %v7 = add i32 %v5, %v6
  ret i32 %v7
}

; Function Attrs: cold noreturn nounwind memory(inaccessiblemem: write)
declare void @llvm.trap() #0

attributes #0 = { cold noreturn nounwind memory(inaccessiblemem: write) }
