; ModuleID = 'astra.scalar'
source_filename = "astra.scalar"

define internal fastcc i32 @astra.fn.0() {
b0:
  br label %b3

b1:                                               ; preds = %b8
  ret i32 1

b2:                                               ; preds = %b8
  ret i32 0

b3:                                               ; preds = %b0
  br label %b4

b4:                                               ; preds = %b3
  %v2 = call fastcc i32 @astra.fn.1(i32 -7, i32 42)
  %v3 = icmp ne i32 %v2, -7
  br i1 %v3, label %b6, label %b5

b5:                                               ; preds = %b4
  %v4 = call fastcc i32 @astra.fn.2(i32 -1, i32 7)
  %v5 = icmp ne i32 %v4, 7
  br label %b6

b6:                                               ; preds = %b5, %b4
  %v0 = phi i1 [ true, %b4 ], [ %v5, %b5 ]
  br i1 %v0, label %b8, label %b7

b7:                                               ; preds = %b6
  %v6 = call fastcc double @astra.fn.3(double 3.500000e+00, double -1.250000e+00)
  %v7 = fcmp une double %v6, -1.250000e+00
  br label %b8

b8:                                               ; preds = %b7, %b6
  %v1 = phi i1 [ true, %b6 ], [ %v7, %b7 ]
  br i1 %v1, label %b1, label %b2
}

define internal fastcc i32 @astra.fn.1(i32 %p0, i32 %p1) {
b0:
  %v2 = icmp slt i32 %p0, %p1
  br i1 %v2, label %b1, label %b2

b1:                                               ; preds = %b0
  ret i32 %p0

b2:                                               ; preds = %b0
  ret i32 %p1
}

define internal fastcc i32 @astra.fn.2(i32 %p0, i32 %p1) {
b0:
  %v2 = icmp ult i32 %p0, %p1
  br i1 %v2, label %b1, label %b2

b1:                                               ; preds = %b0
  ret i32 %p0

b2:                                               ; preds = %b0
  ret i32 %p1
}

define internal fastcc double @astra.fn.3(double %p0, double %p1) {
b0:
  %v2 = fcmp olt double %p0, %p1
  br i1 %v2, label %b1, label %b2

b1:                                               ; preds = %b0
  ret double %p0

b2:                                               ; preds = %b0
  ret double %p1
}
