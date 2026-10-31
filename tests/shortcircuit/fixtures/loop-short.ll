; ModuleID = 'astra.scalar'
source_filename = "astra.scalar"

define internal fastcc i32 @astra.fn.0(i32 %p0) {
b0:
  br label %b1

b1:                                               ; preds = %b2, %b0
  %v1 = phi i32 [ 0, %b0 ], [ %v5, %b2 ]
  br label %b4

b2:                                               ; preds = %b6
  %v5 = add i32 %v1, 1
  br label %b1

b3:                                               ; preds = %b6
  ret i32 %v1

b4:                                               ; preds = %b1
  %v3 = icmp slt i32 %v1, %p0
  br i1 %v3, label %b5, label %b6

b5:                                               ; preds = %b4
  %v4 = icmp slt i32 %v1, 5
  br label %b6

b6:                                               ; preds = %b5, %b4
  %v2 = phi i1 [ false, %b4 ], [ %v4, %b5 ]
  br i1 %v2, label %b2, label %b3
}

define internal fastcc i1 @astra.fn.1(i32 %p0) {
b0:
  %v1 = icmp slt i32 %p0, 5
  ret i1 %v1
}

define internal fastcc i32 @astra.fn.2(i32 %p0) {
b0:
  br label %b1

b1:                                               ; preds = %b2, %b0
  %v1 = phi i32 [ 0, %b0 ], [ %v5, %b2 ]
  br label %b4

b2:                                               ; preds = %b6
  %v5 = add i32 %v1, 1
  br label %b1

b3:                                               ; preds = %b6
  ret i32 %v1

b4:                                               ; preds = %b1
  %v3 = icmp slt i32 %v1, %p0
  br i1 %v3, label %b5, label %b6

b5:                                               ; preds = %b4
  %v4 = call fastcc i1 @astra.fn.1(i32 %v1)
  br label %b6

b6:                                               ; preds = %b5, %b4
  %v2 = phi i1 [ false, %b4 ], [ %v4, %b5 ]
  br i1 %v2, label %b2, label %b3
}

define internal fastcc i32 @astra.fn.3(i32 %p0) {
b0:
  br label %b1

b1:                                               ; preds = %b8, %b0
  %v1 = phi i32 [ 0, %b0 ], [ %v6, %b8 ]
  br label %b4

b2:                                               ; preds = %b6
  %v6 = add i32 %v1, 1
  %v7 = icmp eq i32 %v6, 3
  br i1 %v7, label %b7, label %b8

b3:                                               ; preds = %b7, %b6
  %v2 = phi i32 [ %v1, %b6 ], [ 8, %b7 ]
  ret i32 %v2

b4:                                               ; preds = %b1
  %v4 = icmp slt i32 %v1, %p0
  br i1 %v4, label %b5, label %b6

b5:                                               ; preds = %b4
  %v5 = call fastcc i1 @astra.fn.1(i32 %v1)
  br label %b6

b6:                                               ; preds = %b5, %b4
  %v3 = phi i1 [ false, %b4 ], [ %v5, %b5 ]
  br i1 %v3, label %b2, label %b3

b7:                                               ; preds = %b2
  br label %b3

b8:                                               ; preds = %b2
  br label %b1
}
