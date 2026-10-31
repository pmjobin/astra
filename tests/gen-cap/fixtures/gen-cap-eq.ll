; ModuleID = 'astra.scalar'
source_filename = "astra.scalar"

define internal fastcc i32 @astra.fn.0() {
b0:
  br label %b3

b1:                                               ; preds = %b8
  ret i32 42

b2:                                               ; preds = %b8
  ret i32 1

b3:                                               ; preds = %b0
  br label %b4

b4:                                               ; preds = %b3
  %v2 = call fastcc i1 @astra.fn.1(i1 true, i1 true)
  br i1 %v2, label %b5, label %b6

b5:                                               ; preds = %b4
  %v3 = call fastcc i1 @astra.fn.2(ptr null, ptr null)
  br label %b6

b6:                                               ; preds = %b5, %b4
  %v0 = phi i1 [ false, %b4 ], [ %v3, %b5 ]
  br i1 %v0, label %b7, label %b8

b7:                                               ; preds = %b6
  %v4 = call fastcc i1 @astra.fn.3(double 1.000000e+00, double 2.000000e+00)
  br label %b8

b8:                                               ; preds = %b7, %b6
  %v1 = phi i1 [ false, %b6 ], [ %v4, %b7 ]
  br i1 %v1, label %b1, label %b2
}

define internal fastcc i1 @astra.fn.1(i1 %p0, i1 %p1) {
b0:
  %v2 = icmp eq i1 %p0, %p1
  ret i1 %v2
}

define internal fastcc i1 @astra.fn.2(ptr %p0, ptr %p1) {
b0:
  %v2 = icmp eq ptr %p0, %p1
  ret i1 %v2
}

define internal fastcc i1 @astra.fn.3(double %p0, double %p1) {
b0:
  %v2 = fcmp une double %p0, %p1
  ret i1 %v2
}
