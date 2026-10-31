; ModuleID = 'astra.scalar'
source_filename = "astra.scalar"

define internal fastcc i32 @astra.fn.0(i1 %p0) {
b0:
  br label %b1

b1:                                               ; preds = %b5, %b0
  %v1 = phi i32 [ 0, %b0 ], [ 2, %b5 ]
  br i1 %p0, label %b2, label %b3

b2:                                               ; preds = %b1
  br i1 true, label %b4, label %b5

b3:                                               ; preds = %b4, %b1
  %v2 = phi i32 [ %v1, %b1 ], [ 1, %b4 ]
  ret i32 %v2

b4:                                               ; preds = %b2
  br label %b3

b5:                                               ; preds = %b2
  br label %b1
}
