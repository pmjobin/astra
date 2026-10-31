; ModuleID = 'astra.scalar'
source_filename = "astra.scalar"

define internal fastcc { i32, double } @astra.fn.0(i1 %p0, i32 %p1, double %p2, i32 %p3, double %p4) {
b0:
  br i1 %p0, label %b1, label %b2

b1:                                               ; preds = %b0
  %struct.return.0 = insertvalue { i32, double } zeroinitializer, i32 %p1, 0
  %struct.return.1 = insertvalue { i32, double } %struct.return.0, double %p2, 1
  ret { i32, double } %struct.return.1

b2:                                               ; preds = %b0
  %struct.return.01 = insertvalue { i32, double } zeroinitializer, i32 %p3, 0
  %struct.return.12 = insertvalue { i32, double } %struct.return.01, double %p4, 1
  ret { i32, double } %struct.return.12
}

define internal fastcc { i32, double } @astra.fn.1(i1 %p0, i32 %p1, double %p2, i32 %p3, double %p4) {
b0:
  br i1 %p0, label %b1, label %b2

b1:                                               ; preds = %b0
  br label %b2

b2:                                               ; preds = %b1, %b0
  %v5 = phi i32 [ %p1, %b0 ], [ %p3, %b1 ]
  %v6 = phi double [ %p2, %b0 ], [ %p4, %b1 ]
  %struct.return.0 = insertvalue { i32, double } zeroinitializer, i32 %v5, 0
  %struct.return.1 = insertvalue { i32, double } %struct.return.0, double %v6, 1
  ret { i32, double } %struct.return.1
}

define internal fastcc i32 @astra.fn.2() {
b0:
  %struct.call = call fastcc { i32, double } @astra.fn.0(i1 true, i32 7, double 3.500000e+00, i32 9, double 9.500000e+00)
  %v5 = extractvalue { i32, double } %struct.call, 0
  %v6 = extractvalue { i32, double } %struct.call, 1
  %struct.call1 = call fastcc { i32, double } @astra.fn.0(i1 false, i32 7, double 3.500000e+00, i32 9, double 9.500000e+00)
  %v7 = extractvalue { i32, double } %struct.call1, 0
  %v8 = extractvalue { i32, double } %struct.call1, 1
  %struct.call2 = call fastcc { i32, double } @astra.fn.1(i1 true, i32 7, double 3.500000e+00, i32 9, double 9.500000e+00)
  %v9 = extractvalue { i32, double } %struct.call2, 0
  %v10 = extractvalue { i32, double } %struct.call2, 1
  %struct.call3 = call fastcc { i32, double } @astra.fn.1(i1 false, i32 7, double 3.500000e+00, i32 9, double 9.500000e+00)
  %v11 = extractvalue { i32, double } %struct.call3, 0
  %v12 = extractvalue { i32, double } %struct.call3, 1
  br label %b3

b1:                                               ; preds = %b17
  ret i32 1

b2:                                               ; preds = %b17
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
  %v13 = icmp ne i32 %v5, 7
  br i1 %v13, label %b9, label %b8

b8:                                               ; preds = %b7
  %v14 = fcmp une double %v6, 3.500000e+00
  br label %b9

b9:                                               ; preds = %b8, %b7
  %v0 = phi i1 [ true, %b7 ], [ %v14, %b8 ]
  br i1 %v0, label %b11, label %b10

b10:                                              ; preds = %b9
  %v15 = icmp ne i32 %v7, 9
  br label %b11

b11:                                              ; preds = %b10, %b9
  %v1 = phi i1 [ true, %b9 ], [ %v15, %b10 ]
  br i1 %v1, label %b13, label %b12

b12:                                              ; preds = %b11
  %v16 = fcmp une double %v8, 9.500000e+00
  br label %b13

b13:                                              ; preds = %b12, %b11
  %v2 = phi i1 [ true, %b11 ], [ %v16, %b12 ]
  br i1 %v2, label %b15, label %b14

b14:                                              ; preds = %b13
  %v17 = icmp ne i32 %v9, 9
  br label %b15

b15:                                              ; preds = %b14, %b13
  %v3 = phi i1 [ true, %b13 ], [ %v17, %b14 ]
  br i1 %v3, label %b17, label %b16

b16:                                              ; preds = %b15
  %v18 = icmp ne i32 %v11, 7
  br label %b17

b17:                                              ; preds = %b16, %b15
  %v4 = phi i1 [ true, %b15 ], [ %v18, %b16 ]
  br i1 %v4, label %b1, label %b2
}
