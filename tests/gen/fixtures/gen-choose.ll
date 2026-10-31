; ModuleID = 'astra.scalar'
source_filename = "astra.scalar"

define internal fastcc i32 @astra.fn.0() {
b0:
  %v1 = call fastcc double @astra.fn.1(i1 true, double 0.000000e+00, double 1.250000e+00)
  %v4 = call fastcc <8 x i16> @astra.fn.2(i1 true, <8 x i16> <i16 1, i16 2, i16 3, i16 4, i16 5, i16 6, i16 7, i16 8>, <8 x i16> <i16 42, i16 2, i16 3, i16 4, i16 5, i16 6, i16 7, i16 8>)
  br label %b3

b1:                                               ; preds = %b5
  %v8 = call fastcc i32 @astra.fn.3(i1 true, i32 0, i32 42)
  ret i32 %v8

b2:                                               ; preds = %b5
  ret i32 1

b3:                                               ; preds = %b0
  %v5 = fcmp oeq double %v1, 1.250000e+00
  br i1 %v5, label %b4, label %b5

b4:                                               ; preds = %b3
  %v6 = extractelement <8 x i16> %v4, i32 0
  %v7 = icmp eq i16 %v6, 42
  br label %b5

b5:                                               ; preds = %b4, %b3
  %v0 = phi i1 [ false, %b3 ], [ %v7, %b4 ]
  br i1 %v0, label %b1, label %b2
}

define internal fastcc double @astra.fn.1(i1 %p0, double %p1, double %p2) {
b0:
  br i1 %p0, label %b1, label %b2

b1:                                               ; preds = %b0
  br label %b2

b2:                                               ; preds = %b1, %b0
  %v3 = phi double [ %p1, %b0 ], [ %p2, %b1 ]
  ret double %v3
}

define internal fastcc <8 x i16> @astra.fn.2(i1 %p0, <8 x i16> %p1, <8 x i16> %p2) {
b0:
  br i1 %p0, label %b1, label %b2

b1:                                               ; preds = %b0
  br label %b2

b2:                                               ; preds = %b1, %b0
  %v3 = phi <8 x i16> [ %p1, %b0 ], [ %p2, %b1 ]
  ret <8 x i16> %v3
}

define internal fastcc i32 @astra.fn.3(i1 %p0, i32 %p1, i32 %p2) {
b0:
  br i1 %p0, label %b1, label %b2

b1:                                               ; preds = %b0
  br label %b2

b2:                                               ; preds = %b1, %b0
  %v3 = phi i32 [ %p1, %b0 ], [ %p2, %b1 ]
  ret i32 %v3
}
