; ModuleID = 'astra.scalar'
source_filename = "astra.scalar"

define internal fastcc i32 @astra.fn.0() {
b0:
  br label %b1

b1:                                               ; preds = %b5, %b0
  %v0 = phi i32 [ 0, %b0 ], [ %v3, %b5 ]
  %v2 = icmp slt i32 %v0, 100
  br i1 %v2, label %b2, label %b3

b2:                                               ; preds = %b1
  %v3 = add i32 %v0, 1
  %v4 = icmp eq i32 %v3, 7
  br i1 %v4, label %b4, label %b5

b3:                                               ; preds = %b4, %b1
  %v1 = phi i32 [ %v0, %b1 ], [ %v3, %b4 ]
  ret i32 %v1

b4:                                               ; preds = %b2
  br label %b3

b5:                                               ; preds = %b2
  br label %b1
}
