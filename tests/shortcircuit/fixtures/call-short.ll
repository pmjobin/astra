; ModuleID = 'astra.scalar'
source_filename = "astra.scalar"

define internal fastcc i1 @astra.fn.0(i1 %p0) {
b0:
  ret i1 %p0
}

define internal fastcc i1 @astra.fn.1(i1 %p0) {
b0:
  ret i1 %p0
}

define internal fastcc i1 @astra.fn.2(i1 %p0, i1 %p1) {
b0:
  %v2 = icmp eq i1 %p0, %p1
  ret i1 %v2
}

define internal fastcc i1 @astra.fn.3(i1 %p0, i1 %p1) {
b0:
  br label %b1

b1:                                               ; preds = %b0
  %v3 = call fastcc i1 @astra.fn.0(i1 %p0)
  br i1 %v3, label %b2, label %b3

b2:                                               ; preds = %b1
  %v4 = call fastcc i1 @astra.fn.1(i1 %p1)
  br label %b3

b3:                                               ; preds = %b2, %b1
  %v2 = phi i1 [ false, %b1 ], [ %v4, %b2 ]
  ret i1 %v2
}

define internal fastcc i1 @astra.fn.4(i1 %p0, i1 %p1) {
b0:
  br label %b1

b1:                                               ; preds = %b0
  %v3 = call fastcc i1 @astra.fn.0(i1 %p0)
  br i1 %v3, label %b3, label %b2

b2:                                               ; preds = %b1
  %v4 = call fastcc i1 @astra.fn.1(i1 %p1)
  br label %b3

b3:                                               ; preds = %b2, %b1
  %v2 = phi i1 [ true, %b1 ], [ %v4, %b2 ]
  ret i1 %v2
}

define internal fastcc i1 @astra.fn.5(i1 %p0, i1 %p1, i1 %p2, i1 %p3) {
b0:
  br label %b1

b1:                                               ; preds = %b0
  %v6 = call fastcc i1 @astra.fn.0(i1 %p0)
  br i1 %v6, label %b2, label %b3

b2:                                               ; preds = %b1
  %v7 = call fastcc i1 @astra.fn.1(i1 %p1)
  br label %b3

b3:                                               ; preds = %b2, %b1
  %v4 = phi i1 [ false, %b1 ], [ %v7, %b2 ]
  br label %b4

b4:                                               ; preds = %b3
  %v8 = call fastcc i1 @astra.fn.0(i1 %p2)
  br i1 %v8, label %b6, label %b5

b5:                                               ; preds = %b4
  %v9 = call fastcc i1 @astra.fn.1(i1 %p3)
  br label %b6

b6:                                               ; preds = %b5, %b4
  %v5 = phi i1 [ true, %b4 ], [ %v9, %b5 ]
  %v10 = call fastcc i1 @astra.fn.2(i1 %v4, i1 %v5)
  ret i1 %v10
}

define internal fastcc i1 @astra.fn.6(i1 %p0, i1 %p1, i1 %p2) {
b0:
  %v4 = call fastcc i1 @astra.fn.0(i1 %p0)
  br label %b1

b1:                                               ; preds = %b0
  br i1 %p1, label %b2, label %b3

b2:                                               ; preds = %b1
  %v5 = call fastcc i1 @astra.fn.1(i1 %p2)
  br label %b3

b3:                                               ; preds = %b2, %b1
  %v3 = phi i1 [ false, %b1 ], [ %v5, %b2 ]
  %v6 = call fastcc i1 @astra.fn.2(i1 %v4, i1 %v3)
  ret i1 %v6
}

define internal fastcc i1 @astra.fn.7(i32 %p0, i32 %p1, i1 %p2, i1 %p3) {
b0:
  %v5.zero = icmp eq i32 %p1, 0
  br i1 %v5.zero, label %v5.trap, label %v5.nonzero

b1:                                               ; preds = %v5.continue
  br i1 %p2, label %b3, label %b2

b2:                                               ; preds = %b1
  br label %b3

b3:                                               ; preds = %b2, %b1
  %v4 = phi i1 [ true, %b1 ], [ %p3, %b2 ]
  %v7 = call fastcc i1 @astra.fn.2(i1 %v6, i1 %v4)
  ret i1 %v7

v5.trap:                                          ; preds = %b0
  call void @llvm.trap()
  unreachable

v5.nonzero:                                       ; preds = %b0
  %v5.minimum = icmp eq i32 %p0, -2147483648
  %v5.minusone = icmp eq i32 %p1, -1
  %v5.overflow = and i1 %v5.minimum, %v5.minusone
  br i1 %v5.overflow, label %v5.special, label %v5.normal

v5.special:                                       ; preds = %v5.nonzero
  br label %v5.continue

v5.normal:                                        ; preds = %v5.nonzero
  %v5.raw = sdiv i32 %p0, %p1
  br label %v5.continue

v5.continue:                                      ; preds = %v5.normal, %v5.special
  %v5 = phi i32 [ -2147483648, %v5.special ], [ %v5.raw, %v5.normal ]
  %v6 = icmp sgt i32 %v5, 0
  br label %b1
}

; Function Attrs: cold noreturn nounwind memory(inaccessiblemem: write)
declare void @llvm.trap() #0

attributes #0 = { cold noreturn nounwind memory(inaccessiblemem: write) }
