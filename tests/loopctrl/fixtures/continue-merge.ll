; ModuleID = 'astra.scalar'
source_filename = "astra.scalar"

define internal fastcc i32 @astra.fn.0(i32 %p0) {
b0:
  br label %b1

b1:                                               ; preds = %b5, %b4, %b0
  %v1 = phi i32 [ 0, %b0 ], [ %v4, %b4 ], [ %v4, %b5 ]
  %v2 = phi i32 [ 0, %b0 ], [ 10, %b4 ], [ 20, %b5 ]
  %v3 = icmp slt i32 %v1, %p0
  br i1 %v3, label %b2, label %b3

b2:                                               ; preds = %b1
  %v4 = add i32 %v1, 1
  %v5 = icmp eq i32 %v4, 2
  br i1 %v5, label %b4, label %b5

b3:                                               ; preds = %b1
  ret i32 %v2

b4:                                               ; preds = %b2
  br label %b1

b5:                                               ; preds = %b2
  br label %b1
}
