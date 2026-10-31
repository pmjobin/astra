; ModuleID = 'astra.scalar'
source_filename = "astra.scalar"

define internal fastcc i32 @astra.fn.0(i32 %p0) {
b0:
  ret i32 %p0
}

define internal fastcc i1 @astra.fn.1(i32 %p0) {
b0:
  %v1 = icmp sgt i32 %p0, 0
  ret i1 %v1
}

define internal fastcc i32 @astra.fn.2(i32 %p0, i32 %p1) {
b0:
  br label %b1

b1:                                               ; preds = %b2, %b0
  %v2 = phi i32 [ %p0, %b0 ], [ %v7, %b2 ]
  %v3.zero = icmp eq i32 %p1, 0
  br i1 %v3.zero, label %v3.trap, label %v3.nonzero

b2:                                               ; preds = %v3.continue
  %v7 = sub i32 %v2, 1
  br label %b1

b3:                                               ; preds = %v3.continue
  ret i32 %v2

v3.trap:                                          ; preds = %b1
  call void @llvm.trap()
  unreachable

v3.nonzero:                                       ; preds = %b1
  %v3.minimum = icmp eq i32 %v2, -2147483648
  %v3.minusone = icmp eq i32 %p1, -1
  %v3.overflow = and i1 %v3.minimum, %v3.minusone
  br i1 %v3.overflow, label %v3.special, label %v3.normal

v3.special:                                       ; preds = %v3.nonzero
  br label %v3.continue

v3.normal:                                        ; preds = %v3.nonzero
  %v3.raw = sdiv i32 %v2, %p1
  br label %v3.continue

v3.continue:                                      ; preds = %v3.normal, %v3.special
  %v3 = phi i32 [ -2147483648, %v3.special ], [ %v3.raw, %v3.normal ]
  %v4 = call fastcc i32 @astra.fn.0(i32 %v2)
  %v5 = add i32 %v3, %v4
  %v6 = call fastcc i1 @astra.fn.1(i32 %v5)
  br i1 %v6, label %b2, label %b3
}

; Function Attrs: cold noreturn nounwind memory(inaccessiblemem: write)
declare void @llvm.trap() #0

attributes #0 = { cold noreturn nounwind memory(inaccessiblemem: write) }
