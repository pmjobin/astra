; ModuleID = 'astra.scalar'
source_filename = "astra.scalar"

define internal fastcc i1 @astra.fn.0(i32 %p0) {
b0:
  %v1 = icmp slt i32 %p0, 4
  ret i1 %v1
}

define internal fastcc i32 @astra.fn.1(i32 %p0) {
b0:
  %v1 = add i32 %p0, 1
  ret i32 %v1
}

define internal fastcc i32 @astra.fn.2() {
b0:
  br label %b1

b1:                                               ; preds = %b2, %b0
  %v0 = phi i32 [ 0, %b0 ], [ %v2, %b2 ]
  %v1 = call fastcc i1 @astra.fn.0(i32 %v0)
  br i1 %v1, label %b2, label %b3

b2:                                               ; preds = %b1
  %v2 = call fastcc i32 @astra.fn.1(i32 %v0)
  br label %b1

b3:                                               ; preds = %b1
  ret i32 %v0
}
