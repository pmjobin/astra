; ModuleID = 'astra.scalar'
source_filename = "astra.scalar"

define internal fastcc double @astra.fn.0() {
b0:
  ret double 0x4340000000000000
}

define internal fastcc double @astra.fn.1() {
b0:
  ret double 0x3FF0000000000001
}

define internal fastcc double @astra.fn.2() {
b0:
  ret double -0.000000e+00
}

define internal fastcc double @astra.fn.3() {
b0:
  ret double 4.940660e-324
}

define internal fastcc double @astra.fn.4() {
b0:
  ret double 0xFFFFFFFFFFFFF
}

define internal fastcc double @astra.fn.5() {
b0:
  ret double 0x10000000000000
}

define internal fastcc double @astra.fn.6() {
b0:
  ret double 0x7FEFFFFFFFFFFFFF
}

define internal fastcc double @astra.fn.7() {
b0:
  ret double 0x7FF0000000000000
}

define internal fastcc double @astra.fn.8() {
b0:
  ret double -0.000000e+00
}

define internal fastcc i32 @astra.fn.9() {
b0:
  br label %b3

b1:                                               ; preds = %b14
  ret i32 1

b2:                                               ; preds = %b14
  br label %b17

b3:                                               ; preds = %b0
  br label %b4

b4:                                               ; preds = %b3
  br label %b5

b5:                                               ; preds = %b4
  br label %b6

b6:                                               ; preds = %b5
  %v5 = call fastcc double @astra.fn.0()
  %v6 = fcmp une double %v5, 0x4340000000000000
  br i1 %v6, label %b8, label %b7

b7:                                               ; preds = %b6
  %v7 = call fastcc double @astra.fn.1()
  %v8 = fcmp oeq double %v7, 1.000000e+00
  br label %b8

b8:                                               ; preds = %b7, %b6
  %v0 = phi i1 [ true, %b6 ], [ %v8, %b7 ]
  br i1 %v0, label %b10, label %b9

b9:                                               ; preds = %b8
  %v9 = call fastcc double @astra.fn.3()
  %v10 = fcmp oeq double %v9, 0.000000e+00
  br label %b10

b10:                                              ; preds = %b9, %b8
  %v1 = phi i1 [ true, %b8 ], [ %v10, %b9 ]
  br i1 %v1, label %b12, label %b11

b11:                                              ; preds = %b10
  %v11 = call fastcc double @astra.fn.5()
  %v12 = call fastcc double @astra.fn.4()
  %v13 = fcmp ole double %v11, %v12
  br label %b12

b12:                                              ; preds = %b11, %b10
  %v2 = phi i1 [ true, %b10 ], [ %v13, %b11 ]
  br i1 %v2, label %b14, label %b13

b13:                                              ; preds = %b12
  %v14 = call fastcc double @astra.fn.6()
  %v15 = call fastcc double @astra.fn.7()
  %v16 = fcmp oge double %v14, %v15
  br label %b14

b14:                                              ; preds = %b13, %b12
  %v3 = phi i1 [ true, %b12 ], [ %v16, %b13 ]
  br i1 %v3, label %b1, label %b2

b15:                                              ; preds = %b19
  ret i32 2

b16:                                              ; preds = %b19
  ret i32 0

b17:                                              ; preds = %b2
  %v17 = call fastcc double @astra.fn.2()
  %v18 = fdiv double 1.000000e+00, %v17
  %v19 = call fastcc double @astra.fn.7()
  %v20 = fneg double %v19
  %v21 = fcmp une double %v18, %v20
  br i1 %v21, label %b19, label %b18

b18:                                              ; preds = %b17
  %v22 = call fastcc double @astra.fn.8()
  %v23 = fdiv double 1.000000e+00, %v22
  %v24 = call fastcc double @astra.fn.7()
  %v25 = fneg double %v24
  %v26 = fcmp une double %v23, %v25
  br label %b19

b19:                                              ; preds = %b18, %b17
  %v4 = phi i1 [ true, %b17 ], [ %v26, %b18 ]
  br i1 %v4, label %b15, label %b16
}
