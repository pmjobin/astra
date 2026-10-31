; ModuleID = 'astra.scalar'
source_filename = "astra.scalar"

define internal fastcc i1 @astra.fn.0(i1 %p0, i32 %p1, i32 %p2) {
b0:
  br label %b1

b1:                                               ; preds = %b0
  br i1 %p0, label %b2, label %b3

b2:                                               ; preds = %b1
  %v4.zero = icmp eq i32 %p2, 0
  br i1 %v4.zero, label %v4.trap, label %v4.nonzero

b3:                                               ; preds = %v4.continue, %b1
  %v3 = phi i1 [ false, %b1 ], [ %v5, %v4.continue ]
  ret i1 %v3

v4.trap:                                          ; preds = %b2
  call void @llvm.trap()
  unreachable

v4.nonzero:                                       ; preds = %b2
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
  %v5 = icmp sgt i32 %v4, 0
  br label %b3
}

define internal fastcc i1 @astra.fn.1(i1 %p0, i32 %p1, i32 %p2) {
b0:
  br label %b1

b1:                                               ; preds = %b0
  br i1 %p0, label %b3, label %b2

b2:                                               ; preds = %b1
  %v4.zero = icmp eq i32 %p2, 0
  br i1 %v4.zero, label %v4.trap, label %v4.nonzero

b3:                                               ; preds = %v4.continue, %b1
  %v3 = phi i1 [ true, %b1 ], [ %v5, %v4.continue ]
  ret i1 %v3

v4.trap:                                          ; preds = %b2
  call void @llvm.trap()
  unreachable

v4.nonzero:                                       ; preds = %b2
  %v4.minimum = icmp eq i32 %p1, -2147483648
  %v4.minusone = icmp eq i32 %p2, -1
  %v4.overflow = and i1 %v4.minimum, %v4.minusone
  br i1 %v4.overflow, label %v4.special, label %v4.normal

v4.special:                                       ; preds = %v4.nonzero
  br label %v4.continue

v4.normal:                                        ; preds = %v4.nonzero
  %v4.raw = srem i32 %p1, %p2
  br label %v4.continue

v4.continue:                                      ; preds = %v4.normal, %v4.special
  %v4 = phi i32 [ 0, %v4.special ], [ %v4.raw, %v4.normal ]
  %v5 = icmp eq i32 %v4, 0
  br label %b3
}

; Function Attrs: cold noreturn nounwind memory(inaccessiblemem: write)
declare void @llvm.trap() #0

attributes #0 = { cold noreturn nounwind memory(inaccessiblemem: write) }
