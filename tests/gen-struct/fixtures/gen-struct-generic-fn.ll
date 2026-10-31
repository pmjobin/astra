; ModuleID = 'astra.scalar'
source_filename = "astra.scalar"

define internal fastcc i32 @astra.fn.0() {
b0:
  br label %b3

b1:                                               ; preds = %b8
  ret i32 1

b2:                                               ; preds = %b8
  br label %b11

b3:                                               ; preds = %b0
  br label %b4

b4:                                               ; preds = %b3
  %v6 = call fastcc i32 @astra.fn.1(i32 42, double 3.500000e+00)
  %v7 = icmp ne i32 %v6, 42
  br i1 %v7, label %b6, label %b5

b5:                                               ; preds = %b4
  %v8 = call fastcc i32 @astra.fn.1(i32 43, double 4.500000e+00)
  %v9 = icmp ne i32 %v8, 43
  br label %b6

b6:                                               ; preds = %b5, %b4
  %v0 = phi i1 [ true, %b4 ], [ %v9, %b5 ]
  br i1 %v0, label %b8, label %b7

b7:                                               ; preds = %b6
  %v10 = call fastcc double @astra.fn.2(double 3.500000e+00, i32 42)
  %v11 = fcmp une double %v10, 3.500000e+00
  br label %b8

b8:                                               ; preds = %b7, %b6
  %v1 = phi i1 [ true, %b6 ], [ %v11, %b7 ]
  br i1 %v1, label %b1, label %b2

b9:                                               ; preds = %b13
  ret i32 2

b10:                                              ; preds = %b13
  br label %b16

b11:                                              ; preds = %b2
  %v12 = call fastcc <8 x i16> @astra.fn.3(<8 x i16> <i16 1, i16 2, i16 3, i16 4, i16 5, i16 6, i16 7, i16 8>, i1 true)
  %v13 = icmp eq <8 x i16> %v12, <i16 1, i16 2, i16 3, i16 4, i16 5, i16 6, i16 7, i16 8>
  %v14.lane0 = extractelement <8 x i1> %v13, i32 0
  %v14.lane1 = extractelement <8 x i1> %v13, i32 1
  %v14.reduce1 = and i1 %v14.lane0, %v14.lane1
  %v14.lane2 = extractelement <8 x i1> %v13, i32 2
  %v14.reduce2 = and i1 %v14.reduce1, %v14.lane2
  %v14.lane3 = extractelement <8 x i1> %v13, i32 3
  %v14.reduce3 = and i1 %v14.reduce2, %v14.lane3
  %v14.lane4 = extractelement <8 x i1> %v13, i32 4
  %v14.reduce4 = and i1 %v14.reduce3, %v14.lane4
  %v14.lane5 = extractelement <8 x i1> %v13, i32 5
  %v14.reduce5 = and i1 %v14.reduce4, %v14.lane5
  %v14.lane6 = extractelement <8 x i1> %v13, i32 6
  %v14.reduce6 = and i1 %v14.reduce5, %v14.lane6
  %v14.lane7 = extractelement <8 x i1> %v13, i32 7
  %v14 = and i1 %v14.reduce6, %v14.lane7
  %v15 = xor i1 %v14, true
  br i1 %v15, label %b13, label %b12

b12:                                              ; preds = %b11
  %v16 = call fastcc <4 x i1> @astra.fn.4(<4 x i1> <i1 true, i1 false, i1 true, i1 false>, i32 7)
  %v17 = icmp eq <4 x i1> %v16, <i1 true, i1 false, i1 true, i1 false>
  %v18.lane0 = extractelement <4 x i1> %v17, i32 0
  %v18.lane1 = extractelement <4 x i1> %v17, i32 1
  %v18.reduce1 = and i1 %v18.lane0, %v18.lane1
  %v18.lane2 = extractelement <4 x i1> %v17, i32 2
  %v18.reduce2 = and i1 %v18.reduce1, %v18.lane2
  %v18.lane3 = extractelement <4 x i1> %v17, i32 3
  %v18 = and i1 %v18.reduce2, %v18.lane3
  %v19 = xor i1 %v18, true
  br label %b13

b13:                                              ; preds = %b12, %b11
  %v2 = phi i1 [ true, %b11 ], [ %v19, %b12 ]
  br i1 %v2, label %b9, label %b10

b14:                                              ; preds = %b18
  ret i32 3

b15:                                              ; preds = %b18
  ret i32 0

b16:                                              ; preds = %b10
  %v20 = call fastcc i8 @astra.fn.5(i8 7, double 1.000000e+00)
  %v21 = icmp ne i8 %v20, 7
  br i1 %v21, label %b18, label %b17

b17:                                              ; preds = %b16
  %v22 = call fastcc i8 @astra.fn.6(i8 8, double 1.000000e+00)
  %v23 = icmp ne i8 %v22, 8
  br label %b18

b18:                                              ; preds = %b17, %b16
  %v3 = phi i1 [ true, %b16 ], [ %v23, %b17 ]
  br i1 %v3, label %b14, label %b15
}

define internal fastcc i32 @astra.fn.1(i32 %p0, double %p1) {
b0:
  ret i32 %p0
}

define internal fastcc double @astra.fn.2(double %p0, i32 %p1) {
b0:
  ret double %p0
}

define internal fastcc <8 x i16> @astra.fn.3(<8 x i16> %p0, i1 %p1) {
b0:
  ret <8 x i16> %p0
}

define internal fastcc <4 x i1> @astra.fn.4(<4 x i1> %p0, i32 %p1) {
b0:
  ret <4 x i1> %p0
}

define internal fastcc i8 @astra.fn.5(i8 %p0, double %p1) {
b0:
  ret i8 %p0
}

define internal fastcc i8 @astra.fn.6(i8 %p0, double %p1) {
b0:
  ret i8 %p0
}
