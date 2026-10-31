; ModuleID = 'astra.scalar'
source_filename = "astra.scalar"

define internal fastcc i32 @astra.fn.0(i1 %p0, i32 %p1, i32 %p2) {
b0:
  br i1 %p0, label %b1, label %b2

b1:                                               ; preds = %b0
  %v4.zero = icmp eq i32 %p2, 0
  br i1 %v4.zero, label %v4.trap, label %v4.nonzero

b2:                                               ; preds = %b0
  %v5.zero = icmp eq i32 %p2, 0
  br i1 %v5.zero, label %v5.trap, label %v5.nonzero

b3:                                               ; preds = %v5.continue, %v4.continue
  %v3 = phi i32 [ %v4, %v4.continue ], [ %v5, %v5.continue ]
  ret i32 %v3

v4.trap:                                          ; preds = %b1
  call void @llvm.trap()
  unreachable

v4.nonzero:                                       ; preds = %b1
  %v4.minimum = icmp eq i32 %p1, -2147483648
  %v4.minusone = icmp eq i32 %p2, -1
  %v4.overflow = and i1 %v4.minimum, %v4.minusone
  br i1 %v4.overflow, label %v4.special, label %v4.normal

v4.special:                                       ; preds = %v4.nonzero
  br label %v4.continue

v4.normal:                                        ; preds = %v4.nonzero
  %v4.raw = sdiv i32 %p1, %p2
  br label %v4.continue

v4.continue:                                      ; preds = %v4.normal, %v4.special
  %v4 = phi i32 [ -2147483648, %v4.special ], [ %v4.raw, %v4.normal ]
  br label %b3

v5.trap:                                          ; preds = %b2
  call void @llvm.trap()
  unreachable

v5.nonzero:                                       ; preds = %b2
  %v5.minimum = icmp eq i32 %p1, -2147483648
  %v5.minusone = icmp eq i32 %p2, -1
  %v5.overflow = and i1 %v5.minimum, %v5.minusone
  br i1 %v5.overflow, label %v5.special, label %v5.normal

v5.special:                                       ; preds = %v5.nonzero
  br label %v5.continue

v5.normal:                                        ; preds = %v5.nonzero
  %v5.raw = srem i32 %p1, %p2
  br label %v5.continue

v5.continue:                                      ; preds = %v5.normal, %v5.special
  %v5 = phi i32 [ 0, %v5.special ], [ %v5.raw, %v5.normal ]
  br label %b3
}

; Function Attrs: cold noreturn nounwind memory(inaccessiblemem: write)
declare void @llvm.trap() #0

attributes #0 = { cold noreturn nounwind memory(inaccessiblemem: write) }
