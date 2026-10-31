; ModuleID = 'astra.scalar'
source_filename = "astra.scalar"

define internal fastcc i32 @astra.fn.0(i32 %p0) {
b0:
  %v1 = add i32 %p0, 1
  ret i32 %v1
}

define internal fastcc i32 @astra.fn.1(i1 %p0, i32 %p1, i32 %p2) {
b0:
  br i1 %p0, label %b1, label %b2

b1:                                               ; preds = %b0
  %v4 = call fastcc i32 @astra.fn.0(i32 %p1)
  br label %b3

b2:                                               ; preds = %b0
  %v5 = call fastcc i32 @astra.fn.0(i32 %p2)
  br label %b3

b3:                                               ; preds = %b2, %b1
  %v3 = phi i32 [ %v4, %b1 ], [ %v5, %b2 ]
  ret i32 %v3
}
