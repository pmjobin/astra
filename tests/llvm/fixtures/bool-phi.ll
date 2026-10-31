; ModuleID = 'astra.scalar'
source_filename = "astra.scalar"

define internal fastcc i1 @astra.fn.0(i1 %p0, i1 %p1, i1 %p2) {
b0:
  br i1 %p0, label %b1, label %b2

b1:                                               ; preds = %b0
  br label %b3

b2:                                               ; preds = %b0
  br label %b3

b3:                                               ; preds = %b2, %b1
  %v3 = phi i1 [ %p1, %b1 ], [ %p2, %b2 ]
  ret i1 %v3
}
