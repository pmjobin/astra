; ModuleID = 'astra.scalar'
source_filename = "astra.scalar"

define internal fastcc float @astra.fn.0() {
b0:
  ret float 0.000000e+00
}

define internal fastcc float @astra.fn.1() {
b0:
  ret float -0.000000e+00
}

define internal fastcc float @astra.fn.2() {
b0:
  ret float 1.000000e+00
}

define internal fastcc float @astra.fn.3() {
b0:
  ret float -1.000000e+00
}

define internal fastcc float @astra.fn.4() {
b0:
  ret float 5.000000e-01
}

define internal fastcc float @astra.fn.5() {
b0:
  ret float 2.000000e+00
}

define internal fastcc float @astra.fn.6() {
b0:
  ret float 0x36A0000000000000
}

define internal fastcc float @astra.fn.7() {
b0:
  ret float 0x3810000000000000
}

define internal fastcc float @astra.fn.8() {
b0:
  ret float 0x47EFFFFFE0000000
}

define internal fastcc float @astra.fn.9() {
b0:
  ret float 0x7FF0000000000000
}

define internal fastcc float @astra.fn.10() {
b0:
  ret float 0.000000e+00
}

define internal fastcc float @astra.fn.11() {
b0:
  ret float 1.000000e+00
}

define internal fastcc float @astra.fn.12() {
b0:
  ret float 0x3FF0000040000000
}

define internal fastcc i32 @astra.fn.13() {
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
  %v11 = call fastcc float @astra.fn.0()
  %v12 = fcmp une float %v11, -0.000000e+00
  br i1 %v12, label %b7, label %b6

b6:                                               ; preds = %b5
  %v13 = call fastcc float @astra.fn.1()
  %v14 = fcmp une float %v13, 0.000000e+00
  br label %b7

b7:                                               ; preds = %b6, %b5
  %v0 = phi i1 [ true, %b5 ], [ %v14, %b6 ]
  br i1 %v0, label %b9, label %b8

b8:                                               ; preds = %b7
  %v15 = call fastcc float @astra.fn.2()
  %v16 = fcmp une float %v15, 1.000000e+00
  br label %b9

b9:                                               ; preds = %b8, %b7
  %v1 = phi i1 [ true, %b7 ], [ %v16, %b8 ]
  br i1 %v1, label %b11, label %b10

b10:                                              ; preds = %b9
  %v17 = call fastcc float @astra.fn.3()
  %v18 = fcmp une float %v17, -1.000000e+00
  br label %b11

b11:                                              ; preds = %b10, %b9
  %v2 = phi i1 [ true, %b9 ], [ %v18, %b10 ]
  br i1 %v2, label %b1, label %b2

b12:                                              ; preds = %b22
  ret i32 2

b13:                                              ; preds = %b22
  br label %b25

b14:                                              ; preds = %b2
  br label %b15

b15:                                              ; preds = %b14
  br label %b16

b16:                                              ; preds = %b15
  %v19 = call fastcc float @astra.fn.4()
  %v20 = fcmp une float %v19, 5.000000e-01
  br i1 %v20, label %b18, label %b17

b17:                                              ; preds = %b16
  %v21 = call fastcc float @astra.fn.5()
  %v22 = fcmp une float %v21, 2.000000e+00
  br label %b18

b18:                                              ; preds = %b17, %b16
  %v3 = phi i1 [ true, %b16 ], [ %v22, %b17 ]
  br i1 %v3, label %b20, label %b19

b19:                                              ; preds = %b18
  %v23 = call fastcc float @astra.fn.6()
  %v24 = fcmp oeq float %v23, 0.000000e+00
  br label %b20

b20:                                              ; preds = %b19, %b18
  %v4 = phi i1 [ true, %b18 ], [ %v24, %b19 ]
  br i1 %v4, label %b22, label %b21

b21:                                              ; preds = %b20
  %v25 = call fastcc float @astra.fn.7()
  %v26 = call fastcc float @astra.fn.6()
  %v27 = fcmp ole float %v25, %v26
  br label %b22

b22:                                              ; preds = %b21, %b20
  %v5 = phi i1 [ true, %b20 ], [ %v27, %b21 ]
  br i1 %v5, label %b12, label %b13

b23:                                              ; preds = %b33
  ret i32 3

b24:                                              ; preds = %b33
  br label %b36

b25:                                              ; preds = %b13
  br label %b26

b26:                                              ; preds = %b25
  br label %b27

b27:                                              ; preds = %b26
  %v28 = call fastcc float @astra.fn.8()
  %v29 = call fastcc float @astra.fn.9()
  %v30 = fcmp oge float %v28, %v29
  br i1 %v30, label %b29, label %b28

b28:                                              ; preds = %b27
  %v31 = call fastcc float @astra.fn.10()
  %v32 = fcmp une float %v31, 0.000000e+00
  br label %b29

b29:                                              ; preds = %b28, %b27
  %v6 = phi i1 [ true, %b27 ], [ %v32, %b28 ]
  br i1 %v6, label %b31, label %b30

b30:                                              ; preds = %b29
  %v33 = call fastcc float @astra.fn.11()
  %v34 = fcmp une float %v33, 1.000000e+00
  br label %b31

b31:                                              ; preds = %b30, %b29
  %v7 = phi i1 [ true, %b29 ], [ %v34, %b30 ]
  br i1 %v7, label %b33, label %b32

b32:                                              ; preds = %b31
  %v35 = call fastcc float @astra.fn.12()
  %v36 = fcmp une float %v35, 0x3FF0000040000000
  br label %b33

b33:                                              ; preds = %b32, %b31
  %v8 = phi i1 [ true, %b31 ], [ %v36, %b32 ]
  br i1 %v8, label %b23, label %b24

b34:                                              ; preds = %b41
  ret i32 4

b35:                                              ; preds = %b41
  ret i32 0

b36:                                              ; preds = %b24
  br label %b37

b37:                                              ; preds = %b36
  br i1 false, label %b39, label %b38

b38:                                              ; preds = %b37
  br label %b39

b39:                                              ; preds = %b38, %b37
  %v9 = phi i1 [ true, %b37 ], [ false, %b38 ]
  br i1 %v9, label %b41, label %b40

b40:                                              ; preds = %b39
  br label %b41

b41:                                              ; preds = %b40, %b39
  %v10 = phi i1 [ true, %b39 ], [ false, %b40 ]
  br i1 %v10, label %b34, label %b35
}
