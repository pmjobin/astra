; ModuleID = 'astra.scalar'
source_filename = "astra.scalar"

define internal fastcc { i32, double, <8 x i16> } @astra.fn.0(i32 %p0, double %p1, <8 x i16> %p2) {
b0:
  %struct.return.0 = insertvalue { i32, double, <8 x i16> } zeroinitializer, i32 %p0, 0
  %struct.return.1 = insertvalue { i32, double, <8 x i16> } %struct.return.0, double %p1, 1
  %struct.return.2 = insertvalue { i32, double, <8 x i16> } %struct.return.1, <8 x i16> %p2, 2
  ret { i32, double, <8 x i16> } %struct.return.2
}

define internal fastcc { i32, double } @astra.fn.1(i32 %p0, double %p1, <8 x i16> %p2) {
b0:
  %struct.return.0 = insertvalue { i32, double } zeroinitializer, i32 %p0, 0
  %struct.return.1 = insertvalue { i32, double } %struct.return.0, double %p1, 1
  ret { i32, double } %struct.return.1
}

define internal fastcc i32 @astra.fn.2() {
b0:
  %struct.call = call fastcc { i32, double, <8 x i16> } @astra.fn.0(i32 7, double 3.500000e+00, <8 x i16> splat (i16 9))
  %v3 = extractvalue { i32, double, <8 x i16> } %struct.call, 0
  %v4 = extractvalue { i32, double, <8 x i16> } %struct.call, 1
  %v5 = extractvalue { i32, double, <8 x i16> } %struct.call, 2
  %struct.call1 = call fastcc { i32, double } @astra.fn.1(i32 %v3, double %v4, <8 x i16> %v5)
  %v6 = extractvalue { i32, double } %struct.call1, 0
  %v7 = extractvalue { i32, double } %struct.call1, 1
  br label %b3

b1:                                               ; preds = %b8
  ret i32 1

b2:                                               ; preds = %b8
  ret i32 0

b3:                                               ; preds = %b0
  br label %b4

b4:                                               ; preds = %b3
  %v8 = icmp ne i32 %v6, 7
  br i1 %v8, label %b6, label %b5

b5:                                               ; preds = %b4
  %v9 = fcmp une double %v7, 3.500000e+00
  br label %b6

b6:                                               ; preds = %b5, %b4
  %v0 = phi i1 [ true, %b4 ], [ %v9, %b5 ]
  br i1 %v0, label %b8, label %b7

b7:                                               ; preds = %b6
  %v10 = extractelement <8 x i16> %v5, i32 7
  %v11 = icmp ne i16 %v10, 9
  br label %b8

b8:                                               ; preds = %b7, %b6
  %v1 = phi i1 [ true, %b6 ], [ %v11, %b7 ]
  br i1 %v1, label %b1, label %b2
}
