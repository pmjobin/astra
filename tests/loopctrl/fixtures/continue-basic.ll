; ModuleID = 'astra.scalar'
source_filename = "astra.scalar"

define internal fastcc i32 @astra.fn.0(i32 %p0) {
b0:
  br label %b1

b1:                                               ; preds = %b5, %b4, %b0
  %v1 = phi i32 [ 0, %b0 ], [ %v4, %b4 ], [ %v4, %b5 ]
  %v2 = phi i32 [ 0, %b0 ], [ %v2, %b4 ], [ %v7, %b5 ]
  %v3 = icmp slt i32 %v1, %p0
  br i1 %v3, label %b2, label %b3

b2:                                               ; preds = %b1
  %v4 = add i32 %v1, 1
  br i1 false, label %v5.trap, label %v5.nonzero

b3:                                               ; preds = %b1
  ret i32 %v2

b4:                                               ; preds = %v5.continue
  br label %b1

b5:                                               ; preds = %v5.continue
  %v7 = add i32 %v2, %v4
  br label %b1

v5.trap:                                          ; preds = %b2
  call void @llvm.trap()
  unreachable

v5.nonzero:                                       ; preds = %b2
  %v5.minimum = icmp eq i32 %v4, -2147483648
  %v5.overflow = and i1 %v5.minimum, false
  br i1 %v5.overflow, label %v5.special, label %v5.normal

v5.special:                                       ; preds = %v5.nonzero
  br label %v5.continue

v5.normal:                                        ; preds = %v5.nonzero
  %v5.raw = srem i32 %v4, 2
  br label %v5.continue

v5.continue:                                      ; preds = %v5.normal, %v5.special
  %v5 = phi i32 [ 0, %v5.special ], [ %v5.raw, %v5.normal ]
  %v6 = icmp eq i32 %v5, 0
  br i1 %v6, label %b4, label %b5
}

; Function Attrs: cold noreturn nounwind memory(inaccessiblemem: write)
declare void @llvm.trap() #0

attributes #0 = { cold noreturn nounwind memory(inaccessiblemem: write) }
