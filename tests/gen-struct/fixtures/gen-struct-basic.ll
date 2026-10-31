; ModuleID = 'astra.scalar'
source_filename = "astra.scalar"

define internal fastcc i32 @astra.fn.0(i32 %p0, double %p1) {
b0:
  %v2 = add i32 %p0, 1
  %v3 = fcmp une double %p1, %p1
  br i1 %v3, label %b1, label %b2

b1:                                               ; preds = %b0
  ret i32 0

b2:                                               ; preds = %b0
  ret i32 %v2
}

define internal fastcc i32 @astra.fn.1() {
b0:
  br label %b3

b1:                                               ; preds = %b8
  ret i32 1

b2:                                               ; preds = %b8
  ret i32 0

b3:                                               ; preds = %b0
  br label %b4

b4:                                               ; preds = %b3
  br i1 false, label %b6, label %b5

b5:                                               ; preds = %b4
  br label %b6

b6:                                               ; preds = %b5, %b4
  %v0 = phi i1 [ true, %b4 ], [ false, %b5 ]
  br i1 %v0, label %b8, label %b7

b7:                                               ; preds = %b6
  %v4 = call fastcc i32 @astra.fn.0(i32 42, double 7.250000e+00)
  %v5 = icmp ne i32 %v4, 43
  br label %b8

b8:                                               ; preds = %b7, %b6
  %v1 = phi i1 [ true, %b6 ], [ %v5, %b7 ]
  br i1 %v1, label %b1, label %b2
}
