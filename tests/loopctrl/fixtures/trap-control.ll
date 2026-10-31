; ModuleID = 'astra.scalar'
source_filename = "astra.scalar"

define internal fastcc i32 @astra.fn.0(i32 %p0, i32 %p1) {
b0:
  br label %b1

b1:                                               ; preds = %b5, %v7.continue, %b0
  %v2 = phi i32 [ 0, %b0 ], [ %v5, %v7.continue ], [ %v5, %b5 ]
  %v3 = phi i32 [ 64, %b0 ], [ %v7, %v7.continue ], [ %v8, %b5 ]
  %v4 = icmp slt i32 %v2, %p0
  br i1 %v4, label %b2, label %b3

b2:                                               ; preds = %b1
  %v5 = add i32 %v2, 1
  %v6 = icmp eq i32 %v5, 2
  br i1 %v6, label %b4, label %b5

b3:                                               ; preds = %b1
  ret i32 %v3

b4:                                               ; preds = %b2
  %v7.zero = icmp eq i32 %p1, 0
  br i1 %v7.zero, label %v7.trap, label %v7.nonzero

b5:                                               ; preds = %b2
  %v8 = sub i32 %v3, 1
  br label %b1

v7.trap:                                          ; preds = %b4
  call void @llvm.trap()
  unreachable

v7.nonzero:                                       ; preds = %b4
  %v7.minimum = icmp eq i32 %v3, -2147483648
  %v7.minusone = icmp eq i32 %p1, -1
  %v7.overflow = and i1 %v7.minimum, %v7.minusone
  br i1 %v7.overflow, label %v7.special, label %v7.normal

v7.special:                                       ; preds = %v7.nonzero
  br label %v7.continue

v7.normal:                                        ; preds = %v7.nonzero
  %v7.raw = sdiv i32 %v3, %p1
  br label %v7.continue

v7.continue:                                      ; preds = %v7.normal, %v7.special
  %v7 = phi i32 [ -2147483648, %v7.special ], [ %v7.raw, %v7.normal ]
  br label %b1
}

define internal fastcc i32 @astra.fn.1(i32 %p0, i32 %p1) {
b0:
  br label %b1

b1:                                               ; preds = %b7, %b0
  %v2 = phi i32 [ 0, %b0 ], [ %v7, %b7 ]
  %v3 = phi i32 [ 64, %b0 ], [ %v12, %b7 ]
  %v6 = icmp slt i32 %v2, %p0
  br i1 %v6, label %b2, label %b3

b2:                                               ; preds = %b1
  %v7 = add i32 %v2, 1
  %v8 = icmp eq i32 %p0, 2
  br i1 %v8, label %b4, label %b5

b3:                                               ; preds = %v11.continue, %v9.continue, %b1
  %v4 = phi i32 [ %v2, %b1 ], [ %v7, %v9.continue ], [ %v7, %v11.continue ]
  %v5 = phi i32 [ %v3, %b1 ], [ %v9, %v9.continue ], [ %v11, %v11.continue ]
  ret i32 %v5

b4:                                               ; preds = %b2
  %v9.zero = icmp eq i32 %p1, 0
  br i1 %v9.zero, label %v9.trap, label %v9.nonzero

b5:                                               ; preds = %b2
  %v10 = icmp eq i32 %v7, 3
  br i1 %v10, label %b6, label %b7

b6:                                               ; preds = %b5
  %v11.zero = icmp eq i32 %p1, 0
  br i1 %v11.zero, label %v11.trap, label %v11.nonzero

b7:                                               ; preds = %b5
  %v12 = sub i32 %v3, 1
  br label %b1

v9.trap:                                          ; preds = %b4
  call void @llvm.trap()
  unreachable

v9.nonzero:                                       ; preds = %b4
  %v9.minimum = icmp eq i32 %v3, -2147483648
  %v9.minusone = icmp eq i32 %p1, -1
  %v9.overflow = and i1 %v9.minimum, %v9.minusone
  br i1 %v9.overflow, label %v9.special, label %v9.normal

v9.special:                                       ; preds = %v9.nonzero
  br label %v9.continue

v9.normal:                                        ; preds = %v9.nonzero
  %v9.raw = sdiv i32 %v3, %p1
  br label %v9.continue

v9.continue:                                      ; preds = %v9.normal, %v9.special
  %v9 = phi i32 [ -2147483648, %v9.special ], [ %v9.raw, %v9.normal ]
  br label %b3

v11.trap:                                         ; preds = %b6
  call void @llvm.trap()
  unreachable

v11.nonzero:                                      ; preds = %b6
  %v11.minimum = icmp eq i32 %v3, -2147483648
  %v11.minusone = icmp eq i32 %p1, -1
  %v11.overflow = and i1 %v11.minimum, %v11.minusone
  br i1 %v11.overflow, label %v11.special, label %v11.normal

v11.special:                                      ; preds = %v11.nonzero
  br label %v11.continue

v11.normal:                                       ; preds = %v11.nonzero
  %v11.raw = srem i32 %v3, %p1
  br label %v11.continue

v11.continue:                                     ; preds = %v11.normal, %v11.special
  %v11 = phi i32 [ 0, %v11.special ], [ %v11.raw, %v11.normal ]
  br label %b3
}

; Function Attrs: cold noreturn nounwind memory(inaccessiblemem: write)
declare void @llvm.trap() #0

attributes #0 = { cold noreturn nounwind memory(inaccessiblemem: write) }
