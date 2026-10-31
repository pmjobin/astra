; ModuleID = 'astra.scalar'
source_filename = "astra.scalar"

define internal fastcc i32 @astra.fn.0(i1 %p0) {
b0:
  br label %b1

b1:                                               ; preds = %b0
  br i1 %p0, label %b2, label %b3

b2:                                               ; preds = %b1
  ret i32 0

b3:                                               ; preds = %b1
  ret i32 0
}

define internal fastcc i32 @astra.fn.1(i1 %p0, i1 %p1) {
b0:
  br label %b1

b1:                                               ; preds = %b0
  br i1 %p0, label %b2, label %b3

b2:                                               ; preds = %b1
  br i1 %p1, label %b4, label %b5

b3:                                               ; preds = %b1
  ret i32 0

b4:                                               ; preds = %b2
  ret i32 0

b5:                                               ; preds = %b2
  ret i32 2
}
