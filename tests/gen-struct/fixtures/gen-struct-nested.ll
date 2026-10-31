; ModuleID = 'astra.scalar'
source_filename = "astra.scalar"

define internal fastcc double @astra.fn.0(double %p0) {
b0:
  ret double %p0
}

define internal fastcc i32 @astra.fn.1() {
b0:
  br label %b3

b1:                                               ; preds = %b11
  ret i32 1

b2:                                               ; preds = %b11
  br label %b14

b3:                                               ; preds = %b0
  br label %b4

b4:                                               ; preds = %b3
  br label %b5

b5:                                               ; preds = %b4
  br i1 false, label %b7, label %b6

b6:                                               ; preds = %b5
  br label %b7

b7:                                               ; preds = %b6, %b5
  %v0 = phi i1 [ true, %b5 ], [ false, %b6 ]
  br i1 %v0, label %b9, label %b8

b8:                                               ; preds = %b7
  br label %b9

b9:                                               ; preds = %b8, %b7
  %v1 = phi i1 [ true, %b7 ], [ false, %b8 ]
  br i1 %v1, label %b11, label %b10

b10:                                              ; preds = %b9
  br label %b11

b11:                                              ; preds = %b10, %b9
  %v2 = phi i1 [ true, %b9 ], [ false, %b10 ]
  br i1 %v2, label %b1, label %b2

b12:                                              ; preds = %b16
  ret i32 2

b13:                                              ; preds = %b16
  ret i32 0

b14:                                              ; preds = %b2
  %v8 = call fastcc double @astra.fn.2(double 1.000000e+00, double 2.000000e+00)
  %v9 = fcmp une double %v8, 2.000000e+00
  br i1 %v9, label %b16, label %b15

b15:                                              ; preds = %b14
  %v10 = call fastcc double @astra.fn.0(double 3.500000e+00)
  %v11 = fcmp une double %v10, 3.500000e+00
  br label %b16

b16:                                              ; preds = %b15, %b14
  %v3 = phi i1 [ true, %b14 ], [ %v11, %b15 ]
  br i1 %v3, label %b12, label %b13
}

define internal fastcc double @astra.fn.2(double %p0, double %p1) {
b0:
  ret double %p1
}
