; ModuleID = 'astra.scalar'
source_filename = "astra.scalar"

define internal fastcc i32 @astra.fn.0(i32 %p0) {
b0:
  %v1 = icmp eq i32 %p0, 0
  br i1 %v1, label %b1, label %b2

b1:                                               ; preds = %b0
  ret i32 0

b2:                                               ; preds = %b0
  %v2 = sub i32 %p0, 1
  %v3 = call fastcc i32 @astra.fn.1(i32 %v2)
  ret i32 %v3
}

define internal fastcc i32 @astra.fn.1(i32 %p0) {
b0:
  %v1 = icmp eq i32 %p0, 0
  br i1 %v1, label %b1, label %b2

b1:                                               ; preds = %b0
  ret i32 0

b2:                                               ; preds = %b0
  %v2 = sub i32 %p0, 1
  %v3 = call fastcc i32 @astra.fn.0(i32 %v2)
  ret i32 %v3
}
