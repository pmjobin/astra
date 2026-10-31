; ModuleID = 'astra.scalar'
source_filename = "astra.scalar"

define internal fastcc i32 @astra.fn.0() {
b0:
  br label %b1

b1:                                               ; preds = %b0
  br i1 true, label %b2, label %b3

b2:                                               ; preds = %b1
  ret i32 1

b3:                                               ; preds = %b1
  ret i32 2
}

define internal fastcc i32 @astra.fn.1() {
b0:
  br label %b1

b1:                                               ; preds = %b2, %b0
  %v0 = phi i32 [ 0, %b0 ], [ %v1, %b2 ]
  br i1 false, label %b2, label %b3

b2:                                               ; preds = %b1
  %v1 = add i32 %v0, 1
  br label %b1

b3:                                               ; preds = %b1
  ret i32 %v0
}
