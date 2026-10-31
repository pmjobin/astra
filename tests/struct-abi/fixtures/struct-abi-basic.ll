; ModuleID = 'astra.scalar'
source_filename = "astra.scalar"

define internal fastcc { i32, double } @astra.fn.0(i32 %p0, double %p1) {
b0:
  %struct.return.0 = insertvalue { i32, double } zeroinitializer, i32 %p0, 0
  %struct.return.1 = insertvalue { i32, double } %struct.return.0, double %p1, 1
  ret { i32, double } %struct.return.1
}

define internal fastcc { i32, double } @astra.fn.1() {
b0:
  ret { i32, double } { i32 7, double 3.500000e+00 }
}

define internal fastcc { i32, double } @astra.fn.2() {
b0:
  %struct.call = call fastcc { i32, double } @astra.fn.1()
  %v0 = extractvalue { i32, double } %struct.call, 0
  %v1 = extractvalue { i32, double } %struct.call, 1
  %struct.call1 = call fastcc { i32, double } @astra.fn.0(i32 %v0, double %v1)
  %v2 = extractvalue { i32, double } %struct.call1, 0
  %v3 = extractvalue { i32, double } %struct.call1, 1
  %struct.return.0 = insertvalue { i32, double } zeroinitializer, i32 %v2, 0
  %struct.return.1 = insertvalue { i32, double } %struct.return.0, double %v3, 1
  ret { i32, double } %struct.return.1
}

define internal fastcc i32 @astra.fn.3(i32 %p0, double %p1, i32 %p2) {
b0:
  %v3 = mul i32 %p0, %p2
  ret i32 %v3
}

define internal fastcc i32 @astra.fn.4() {
b0:
  %struct.call = call fastcc { i32, double } @astra.fn.1()
  %v2 = extractvalue { i32, double } %struct.call, 0
  %v3 = extractvalue { i32, double } %struct.call, 1
  %struct.call1 = call fastcc { i32, double } @astra.fn.0(i32 %v2, double %v3)
  %v4 = extractvalue { i32, double } %struct.call1, 0
  %v5 = extractvalue { i32, double } %struct.call1, 1
  %struct.call2 = call fastcc { i32, double } @astra.fn.2()
  %v6 = extractvalue { i32, double } %struct.call2, 0
  %v7 = extractvalue { i32, double } %struct.call2, 1
  br label %b3

b1:                                               ; preds = %b8
  ret i32 1

b2:                                               ; preds = %b8
  ret i32 0

b3:                                               ; preds = %b0
  br label %b4

b4:                                               ; preds = %b3
  %v8 = call fastcc i32 @astra.fn.3(i32 %v6, double %v7, i32 2)
  %v9 = icmp ne i32 %v8, 14
  br i1 %v9, label %b6, label %b5

b5:                                               ; preds = %b4
  %v10 = icmp ne i32 %v2, 7
  br label %b6

b6:                                               ; preds = %b5, %b4
  %v0 = phi i1 [ true, %b4 ], [ %v10, %b5 ]
  br i1 %v0, label %b8, label %b7

b7:                                               ; preds = %b6
  %v11 = fcmp une double %v7, 3.500000e+00
  br label %b8

b8:                                               ; preds = %b7, %b6
  %v1 = phi i1 [ true, %b6 ], [ %v11, %b7 ]
  br i1 %v1, label %b1, label %b2
}
