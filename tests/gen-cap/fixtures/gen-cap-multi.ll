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
  %v2 = call fastcc i1 @astra.fn.1(double 1.000000e+00, double 2.000000e+00)
  br i1 %v2, label %b5, label %b6

b5:                                               ; preds = %b4
  %v3 = call fastcc i32 @astra.fn.2(i32 40, i32 1, i1 true)
  %v4 = icmp eq i32 %v3, 40
  br label %b6

b6:                                               ; preds = %b5, %b4
  %v0 = phi i1 [ false, %b4 ], [ %v4, %b5 ]
  br i1 %v0, label %b7, label %b8

b7:                                               ; preds = %b6
  %v5 = call fastcc i32 @astra.fn.3()
  %v6 = icmp eq i32 %v5, 1
  br label %b8

b8:                                               ; preds = %b7, %b6
  %v1 = phi i1 [ false, %b6 ], [ %v6, %b7 ]
  br i1 %v1, label %b1, label %b2
}

define internal fastcc i1 @astra.fn.1(double %p0, double %p1) {
b0:
  br label %b1

b1:                                               ; preds = %b0
  %v3 = fcmp oeq double %p0, %p1
  br i1 %v3, label %b3, label %b2

b2:                                               ; preds = %b1
  %v4 = fcmp olt double %p0, %p1
  br label %b3

b3:                                               ; preds = %b2, %b1
  %v2 = phi i1 [ true, %b1 ], [ %v4, %b2 ]
  ret i1 %v2
}

define internal fastcc i32 @astra.fn.2(i32 %p0, i32 %p1, i1 %p2) {
b0:
  %v3 = icmp eq i1 %p2, %p2
  br i1 %v3, label %b1, label %b2

b1:                                               ; preds = %b0
  %v4 = add i32 %p0, %p1
  %v5 = xor i32 %v4, %p1
  ret i32 %v5

b2:                                               ; preds = %b0
  ret i32 %p0
}

define internal fastcc i32 @astra.fn.3() {
b0:
  ret i32 1
}
