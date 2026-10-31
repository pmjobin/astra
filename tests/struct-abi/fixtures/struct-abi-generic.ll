; ModuleID = 'astra.scalar'
source_filename = "astra.scalar"

define internal fastcc i32 @astra.fn.0(i32 %p0) {
b0:
  ret i32 %p0
}

define internal fastcc double @astra.fn.1(double %p0) {
b0:
  ret double %p0
}

define internal fastcc <8 x i16> @astra.fn.2(<8 x i16> %p0) {
b0:
  ret <8 x i16> %p0
}

define internal fastcc <4 x i1> @astra.fn.3(<4 x i1> %p0) {
b0:
  ret <4 x i1> %p0
}

define internal fastcc { double, double, i32 } @astra.fn.4(double %p0, double %p1, i32 %p2) {
b0:
  %struct.return.0 = insertvalue { double, double, i32 } zeroinitializer, double %p0, 0
  %struct.return.1 = insertvalue { double, double, i32 } %struct.return.0, double %p1, 1
  %struct.return.2 = insertvalue { double, double, i32 } %struct.return.1, i32 %p2, 2
  ret { double, double, i32 } %struct.return.2
}

define internal fastcc i32 @astra.fn.5() {
b0:
  %struct.call = call fastcc i32 @astra.fn.0(i32 7)
  %struct.call1 = call fastcc double @astra.fn.1(double 3.500000e+00)
  %struct.call2 = call fastcc <8 x i16> @astra.fn.2(<8 x i16> splat (i16 9))
  %struct.call3 = call fastcc <4 x i1> @astra.fn.3(<4 x i1> splat (i1 true))
  %struct.call4 = call fastcc { double, double, i32 } @astra.fn.4(double 1.500000e+00, double 3.500000e+00, i32 7)
  %v13 = extractvalue { double, double, i32 } %struct.call4, 0
  %v14 = extractvalue { double, double, i32 } %struct.call4, 1
  %v15 = extractvalue { double, double, i32 } %struct.call4, 2
  br label %b3

b1:                                               ; preds = %b23
  ret i32 1

b2:                                               ; preds = %b23
  ret i32 0

b3:                                               ; preds = %b0
  br label %b4

b4:                                               ; preds = %b3
  br label %b5

b5:                                               ; preds = %b4
  br label %b6

b6:                                               ; preds = %b5
  br label %b7

b7:                                               ; preds = %b6
  br label %b8

b8:                                               ; preds = %b7
  br label %b9

b9:                                               ; preds = %b8
  %v16 = icmp ne i32 %struct.call, 7
  br i1 %v16, label %b11, label %b10

b10:                                              ; preds = %b9
  %v17 = fcmp une double %struct.call1, 3.500000e+00
  br label %b11

b11:                                              ; preds = %b10, %b9
  %v0 = phi i1 [ true, %b9 ], [ %v17, %b10 ]
  br i1 %v0, label %b13, label %b12

b12:                                              ; preds = %b11
  %v18 = extractelement <8 x i16> %struct.call2, i32 7
  %v19 = icmp ne i16 %v18, 9
  br label %b13

b13:                                              ; preds = %b12, %b11
  %v1 = phi i1 [ true, %b11 ], [ %v19, %b12 ]
  br i1 %v1, label %b15, label %b14

b14:                                              ; preds = %b13
  %v20 = extractelement <4 x i1> %struct.call3, i32 3
  %v21 = xor i1 %v20, true
  br label %b15

b15:                                              ; preds = %b14, %b13
  %v2 = phi i1 [ true, %b13 ], [ %v21, %b14 ]
  br i1 %v2, label %b17, label %b16

b16:                                              ; preds = %b15
  %v22 = fcmp une double %v13, 1.500000e+00
  br label %b17

b17:                                              ; preds = %b16, %b15
  %v3 = phi i1 [ true, %b15 ], [ %v22, %b16 ]
  br i1 %v3, label %b19, label %b18

b18:                                              ; preds = %b17
  %v23 = fcmp une double %v14, 3.500000e+00
  br label %b19

b19:                                              ; preds = %b18, %b17
  %v4 = phi i1 [ true, %b17 ], [ %v23, %b18 ]
  br i1 %v4, label %b21, label %b20

b20:                                              ; preds = %b19
  %v24 = icmp ne i32 %v15, 7
  br label %b21

b21:                                              ; preds = %b20, %b19
  %v5 = phi i1 [ true, %b19 ], [ %v24, %b20 ]
  br i1 %v5, label %b23, label %b22

b22:                                              ; preds = %b21
  %v25 = call fastcc i32 @astra.fn.6(i32 7)
  %v26 = icmp ne i32 %v25, 7
  br label %b23

b23:                                              ; preds = %b22, %b21
  %v6 = phi i1 [ true, %b21 ], [ %v26, %b22 ]
  br i1 %v6, label %b1, label %b2
}

define internal fastcc i32 @astra.fn.6(i32 %p0) {
b0:
  %struct.call = call fastcc i32 @astra.fn.0(i32 7)
  %v2 = icmp eq i32 %struct.call, 7
  br i1 %v2, label %b1, label %b2

b1:                                               ; preds = %b0
  ret i32 %p0

b2:                                               ; preds = %b0
  ret i32 %p0
}
