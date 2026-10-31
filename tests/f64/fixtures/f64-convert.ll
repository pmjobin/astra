; ModuleID = 'astra.scalar'
source_filename = "astra.scalar"

define internal fastcc double @astra.fn.0(float %p0) {
b0:
  %v1 = fpext float %p0 to double
  ret double %v1
}

define internal fastcc float @astra.fn.1(double %p0) {
b0:
  %v1 = fptrunc double %p0 to float
  ret float %v1
}

define internal fastcc i32 @astra.fn.2() {
b0:
  br label %b3

b1:                                               ; preds = %b5
  ret i32 1

b2:                                               ; preds = %b5
  br label %b8

b3:                                               ; preds = %b0
  %v6 = call fastcc float @astra.fn.1(double 0x3FF0000010000000)
  %v7 = fcmp une float %v6, 1.000000e+00
  br i1 %v7, label %b5, label %b4

b4:                                               ; preds = %b3
  %v8 = call fastcc float @astra.fn.1(double 0x3FF0000030000000)
  %v9 = fcmp une float %v8, 0x3FF0000040000000
  br label %b5

b5:                                               ; preds = %b4, %b3
  %v0 = phi i1 [ true, %b3 ], [ %v9, %b4 ]
  br i1 %v0, label %b1, label %b2

b6:                                               ; preds = %b16
  ret i32 2

b7:                                               ; preds = %b16
  br label %b19

b8:                                               ; preds = %b2
  br label %b9

b9:                                               ; preds = %b8
  br label %b10

b10:                                              ; preds = %b9
  %v10 = call fastcc float @astra.fn.1(double 1.000000e+300)
  %v11 = fcmp une float %v10, 0x7FF0000000000000
  br i1 %v11, label %b12, label %b11

b11:                                              ; preds = %b10
  %v12 = call fastcc float @astra.fn.1(double -1.000000e+300)
  %v13 = fcmp une float %v12, 0xFFF0000000000000
  br label %b12

b12:                                              ; preds = %b11, %b10
  %v1 = phi i1 [ true, %b10 ], [ %v13, %b11 ]
  br i1 %v1, label %b14, label %b13

b13:                                              ; preds = %b12
  %v14 = call fastcc float @astra.fn.1(double 1.000000e-300)
  %v15 = fcmp une float %v14, 0.000000e+00
  br label %b14

b14:                                              ; preds = %b13, %b12
  %v2 = phi i1 [ true, %b12 ], [ %v15, %b13 ]
  br i1 %v2, label %b16, label %b15

b15:                                              ; preds = %b14
  %v16 = call fastcc float @astra.fn.1(double -1.000000e-300)
  %v17 = fdiv float 1.000000e+00, %v16
  %v18 = fcmp une float %v17, 0xFFF0000000000000
  br label %b16

b16:                                              ; preds = %b15, %b14
  %v3 = phi i1 [ true, %b14 ], [ %v18, %b15 ]
  br i1 %v3, label %b6, label %b7

b17:                                              ; preds = %b21
  ret i32 3

b18:                                              ; preds = %b21
  br label %b24

b19:                                              ; preds = %b7
  %v19 = call fastcc float @astra.fn.1(double 0x36A0000000000000)
  %v20 = call fastcc double @astra.fn.0(float %v19)
  %v21 = fcmp oeq double %v20, 0.000000e+00
  br i1 %v21, label %b21, label %b20

b20:                                              ; preds = %b19
  %v22 = call fastcc double @astra.fn.0(float -0.000000e+00)
  %v23 = fdiv double 1.000000e+00, %v22
  %v24 = fcmp une double %v23, 0xFFF0000000000000
  br label %b21

b21:                                              ; preds = %b20, %b19
  %v4 = phi i1 [ true, %b19 ], [ %v24, %b20 ]
  br i1 %v4, label %b17, label %b18

b22:                                              ; preds = %b26
  ret i32 4

b23:                                              ; preds = %b26
  ret i32 0

b24:                                              ; preds = %b18
  %v25 = call fastcc double @astra.fn.0(float 0x3FF0000020000000)
  %v26 = call fastcc float @astra.fn.1(double %v25)
  %v27 = fcmp une float %v26, 0x3FF0000020000000
  br i1 %v27, label %b26, label %b25

b25:                                              ; preds = %b24
  %v28 = call fastcc double @astra.fn.0(float 0x3FF0000020000000)
  %v29 = fcmp une double %v28, 0x3FF0000020000000
  br label %b26

b26:                                              ; preds = %b25, %b24
  %v5 = phi i1 [ true, %b24 ], [ %v29, %b25 ]
  br i1 %v5, label %b22, label %b23
}
