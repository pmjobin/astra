; ModuleID = 'astra.scalar'
source_filename = "astra.scalar"

define internal fastcc i32 @astra.fn.0(i32 %p0) {
b0:
  br label %b1

b1:                                               ; preds = %b2, %b0
  %v1 = phi i32 [ 0, %b0 ], [ %v5, %b2 ]
  %v2 = phi i1 [ false, %b0 ], [ %v4, %b2 ]
  %v3 = icmp slt i32 %v1, %p0
  br i1 %v3, label %b2, label %b3

b2:                                               ; preds = %b1
  %v4 = xor i1 %v2, true
  %v5 = add i32 %v1, 1
  br label %b1

b3:                                               ; preds = %b1
  br i1 %v2, label %b4, label %b5

b4:                                               ; preds = %b3
  ret i32 1

b5:                                               ; preds = %b3
  ret i32 0
}
