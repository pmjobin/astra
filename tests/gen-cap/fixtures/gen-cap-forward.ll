; ModuleID = 'astra.scalar'
source_filename = "astra.scalar"

define internal fastcc i32 @astra.fn.0() {
b0:
  %v3 = call fastcc i32 @astra.fn.1(i32 40, i32 2, i1 true)
  %v4 = call fastcc i32 @astra.fn.1(i32 40, i32 2, i1 false)
  %v5 = call fastcc i8 @astra.fn.2(i8 1, i8 2)
  %v6 = call fastcc i8 @astra.fn.3(i8 1, i8 2)
  br label %b3

b1:                                               ; preds = %b11
  ret i32 %v3

b2:                                               ; preds = %b11
  ret i32 1

b3:                                               ; preds = %b0
  br label %b4

b4:                                               ; preds = %b3
  br label %b5

b5:                                               ; preds = %b4
  %v7 = icmp eq i32 %v3, %v4
  br i1 %v7, label %b6, label %b7

b6:                                               ; preds = %b5
  %v8 = icmp eq i8 %v5, 3
  br label %b7

b7:                                               ; preds = %b6, %b5
  %v0 = phi i1 [ false, %b5 ], [ %v8, %b6 ]
  br i1 %v0, label %b8, label %b9

b8:                                               ; preds = %b7
  %v9 = icmp eq i8 %v6, 3
  br label %b9

b9:                                               ; preds = %b8, %b7
  %v1 = phi i1 [ false, %b7 ], [ %v9, %b8 ]
  br i1 %v1, label %b10, label %b11

b10:                                              ; preds = %b9
  %v10 = call fastcc i32 @astra.fn.4()
  %v11 = call fastcc i32 @astra.fn.5()
  %v12 = icmp eq i32 %v10, %v11
  br label %b11

b11:                                              ; preds = %b10, %b9
  %v2 = phi i1 [ false, %b9 ], [ %v12, %b10 ]
  br i1 %v2, label %b1, label %b2
}

define internal fastcc i32 @astra.fn.1(i32 %p0, i32 %p1, i1 %p2) {
b0:
  %v3 = icmp eq i1 %p2, %p2
  br i1 %v3, label %b1, label %b2

b1:                                               ; preds = %b0
  %v4 = call fastcc i32 @astra.fn.6(i32 %p0, i32 %p1)
  ret i32 %v4

b2:                                               ; preds = %b0
  ret i32 %p0
}

define internal fastcc i8 @astra.fn.2(i8 %p0, i8 %p1) {
b0:
  %v2 = add i8 %p0, %p1
  ret i8 %v2
}

define internal fastcc i8 @astra.fn.3(i8 %p0, i8 %p1) {
b0:
  %v2 = add i8 %p0, %p1
  ret i8 %v2
}

define internal fastcc i32 @astra.fn.4() {
b0:
  ret i32 1
}

define internal fastcc i32 @astra.fn.5() {
b0:
  ret i32 1
}

define internal fastcc i32 @astra.fn.6(i32 %p0, i32 %p1) {
b0:
  %v2 = add i32 %p0, %p1
  ret i32 %v2
}
