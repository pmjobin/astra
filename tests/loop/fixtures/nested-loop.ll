; ModuleID = 'astra.scalar'
source_filename = "astra.scalar"

define internal fastcc i32 @astra.fn.0(i32 %p0, i32 %p1) {
b0:
  br label %b1

b1:                                               ; preds = %b6, %b0
  %v2 = phi i32 [ 0, %b0 ], [ %v10, %b6 ]
  %v3 = phi i32 [ 0, %b0 ], [ %v4, %b6 ]
  %v6 = icmp slt i32 %v2, %p0
  br i1 %v6, label %b2, label %b3

b2:                                               ; preds = %b1
  br label %b4

b3:                                               ; preds = %b1
  ret i32 %v3

b4:                                               ; preds = %b5, %b2
  %v4 = phi i32 [ %v3, %b2 ], [ %v8, %b5 ]
  %v5 = phi i32 [ 0, %b2 ], [ %v9, %b5 ]
  %v7 = icmp slt i32 %v5, %p1
  br i1 %v7, label %b5, label %b6

b5:                                               ; preds = %b4
  %v8 = add i32 %v4, 1
  %v9 = add i32 %v5, 1
  br label %b4

b6:                                               ; preds = %b4
  %v10 = add i32 %v2, 1
  br label %b1
}
