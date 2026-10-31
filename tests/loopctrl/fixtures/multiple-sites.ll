; ModuleID = 'astra.scalar'
source_filename = "astra.scalar"

define internal fastcc i32 @astra.fn.0(i32 %p0) {
b0:
  br label %b1

b1:                                               ; preds = %b7, %b6, %b4, %b0
  %v1 = phi i32 [ 0, %b0 ], [ %v4, %b4 ], [ %v4, %b6 ], [ %v4, %b7 ]
  %v2 = phi i32 [ 0, %b0 ], [ %v7, %b4 ], [ %v10, %b6 ], [ %v11, %b7 ]
  %v3 = icmp slt i32 %v1, %p0
  br i1 %v3, label %b2, label %b3

b2:                                               ; preds = %b1
  %v4 = add i32 %v1, 1
  br i1 false, label %v5.trap, label %v5.nonzero

b3:                                               ; preds = %b1
  ret i32 %v2

b4:                                               ; preds = %v5.continue
  %v7 = add i32 %v2, 10
  br label %b1

b5:                                               ; preds = %v5.continue
  br i1 false, label %v8.trap, label %v8.nonzero

b6:                                               ; preds = %v8.continue
  %v10 = add i32 %v2, 100
  br label %b1

b7:                                               ; preds = %v8.continue
  %v11 = add i32 %v2, 1
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
  %v5.raw = srem i32 %v4, 3
  br label %v5.continue

v5.continue:                                      ; preds = %v5.normal, %v5.special
  %v5 = phi i32 [ 0, %v5.special ], [ %v5.raw, %v5.normal ]
  %v6 = icmp eq i32 %v5, 0
  br i1 %v6, label %b4, label %b5

v8.trap:                                          ; preds = %b5
  call void @llvm.trap()
  unreachable

v8.nonzero:                                       ; preds = %b5
  %v8.minimum = icmp eq i32 %v4, -2147483648
  %v8.overflow = and i1 %v8.minimum, false
  br i1 %v8.overflow, label %v8.special, label %v8.normal

v8.special:                                       ; preds = %v8.nonzero
  br label %v8.continue

v8.normal:                                        ; preds = %v8.nonzero
  %v8.raw = srem i32 %v4, 3
  br label %v8.continue

v8.continue:                                      ; preds = %v8.normal, %v8.special
  %v8 = phi i32 [ 0, %v8.special ], [ %v8.raw, %v8.normal ]
  %v9 = icmp eq i32 %v8, 1
  br i1 %v9, label %b6, label %b7
}

define internal fastcc i32 @astra.fn.1(i32 %p0) {
b0:
  br label %b1

b1:                                               ; preds = %b7, %b0
  %v1 = phi i32 [ 0, %b0 ], [ %v6, %b7 ]
  %v2 = phi i32 [ 5, %b0 ], [ %v8, %b7 ]
  %v5 = icmp slt i32 %v1, %p0
  br i1 %v5, label %b2, label %b3

b2:                                               ; preds = %b1
  %v6 = add i32 %v1, 1
  %v7 = icmp eq i32 %p0, 2
  br i1 %v7, label %b4, label %b5

b3:                                               ; preds = %b6, %b4, %b1
  %v3 = phi i32 [ %v1, %b1 ], [ %v6, %b4 ], [ %v6, %b6 ]
  %v4 = phi i32 [ %v2, %b1 ], [ 10, %b4 ], [ 20, %b6 ]
  ret i32 %v4

b4:                                               ; preds = %b2
  br label %b3

b5:                                               ; preds = %b2
  %v8 = add i32 %v2, 1
  %v9 = icmp eq i32 %v6, 3
  br i1 %v9, label %b6, label %b7

b6:                                               ; preds = %b5
  br label %b3

b7:                                               ; preds = %b5
  br label %b1
}

; Function Attrs: cold noreturn nounwind memory(inaccessiblemem: write)
declare void @llvm.trap() #0

attributes #0 = { cold noreturn nounwind memory(inaccessiblemem: write) }
