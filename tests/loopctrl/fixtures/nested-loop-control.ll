; ModuleID = 'astra.scalar'
source_filename = "astra.scalar"

define internal fastcc i32 @astra.fn.0(i32 %p0, i32 %p1) {
b0:
  br label %b1

b1:                                               ; preds = %b14, %b11, %b0
  %v2 = phi i32 [ 0, %b0 ], [ %v15, %b11 ], [ %v15, %b14 ]
  %v3 = phi i32 [ 0, %b0 ], [ %v6, %b11 ], [ %v6, %b14 ]
  %v9 = icmp slt i32 %v2, %p0
  br i1 %v9, label %b2, label %b3

b2:                                               ; preds = %b1
  br label %b4

b3:                                               ; preds = %b13, %b1
  %v4 = phi i32 [ %v2, %b1 ], [ %v15, %b13 ]
  %v5 = phi i32 [ %v3, %b1 ], [ %v6, %b13 ]
  ret i32 %v5

b4:                                               ; preds = %b10, %b7, %b2
  %v6 = phi i32 [ %v3, %b2 ], [ %v6, %b7 ], [ %v14, %b10 ]
  %v7 = phi i32 [ 0, %b2 ], [ %v11, %b7 ], [ %v11, %b10 ]
  %v10 = icmp slt i32 %v7, %p1
  br i1 %v10, label %b5, label %b6

b5:                                               ; preds = %b4
  %v11 = add i32 %v7, 1
  %v12 = icmp eq i32 %v11, 2
  br i1 %v12, label %b7, label %b8

b6:                                               ; preds = %b9, %b4
  %v8 = phi i32 [ %v7, %b4 ], [ %v11, %b9 ]
  %v15 = add i32 %v2, 1
  %v16 = icmp eq i32 %v15, 2
  br i1 %v16, label %b11, label %b12

b7:                                               ; preds = %b5
  br label %b4

b8:                                               ; preds = %b5
  %v13 = icmp eq i32 %v11, 4
  br i1 %v13, label %b9, label %b10

b9:                                               ; preds = %b8
  br label %b6

b10:                                              ; preds = %b8
  %v14 = add i32 %v6, 1
  br label %b4

b11:                                              ; preds = %b6
  br label %b1

b12:                                              ; preds = %b6
  %v17 = icmp eq i32 %v15, 4
  br i1 %v17, label %b13, label %b14

b13:                                              ; preds = %b12
  br label %b3

b14:                                              ; preds = %b12
  br label %b1
}
