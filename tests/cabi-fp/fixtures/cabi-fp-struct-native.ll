; ModuleID = 'astra.scalar'
source_filename = "astra.scalar"

define internal fastcc { i32, double, float } @astra.fn.0(i32 %p0, double %p1, float %p2) {
b0:
  %v3 = call double @c_echo(double %p1)
  %v4 = call float @c_echo32(float %p2)
  %struct.return.0 = insertvalue { i32, double, float } zeroinitializer, i32 %p0, 0
  %struct.return.1 = insertvalue { i32, double, float } %struct.return.0, double %v3, 1
  %struct.return.2 = insertvalue { i32, double, float } %struct.return.1, float %v4, 2
  ret { i32, double, float } %struct.return.2
}

define internal fastcc { i32, double, float } @astra.fn.1(i32 %p0) {
b0:
  %v1 = call double @c_pattern(i32 %p0)
  %v2 = call float @c_pattern32(i32 %p0)
  %struct.call = call fastcc { i32, double, float } @astra.fn.0(i32 %p0, double %v1, float %v2)
  %v3 = extractvalue { i32, double, float } %struct.call, 0
  %v4 = extractvalue { i32, double, float } %struct.call, 1
  %v5 = extractvalue { i32, double, float } %struct.call, 2
  %struct.return.0 = insertvalue { i32, double, float } zeroinitializer, i32 %v3, 0
  %struct.return.1 = insertvalue { i32, double, float } %struct.return.0, double %v4, 1
  %struct.return.2 = insertvalue { i32, double, float } %struct.return.1, float %v5, 2
  ret { i32, double, float } %struct.return.2
}

define internal fastcc i32 @astra.fn.2() {
b0:
  br label %b1

b1:                                               ; preds = %b5, %b0
  %v0 = phi i32 [ 0, %b0 ], [ %v13, %b5 ]
  %v3 = call i32 @c_count()
  %v4 = icmp slt i32 %v0, %v3
  br i1 %v4, label %b2, label %b3

b2:                                               ; preds = %b1
  %struct.call = call fastcc { i32, double, float } @astra.fn.1(i32 %v0)
  %v5 = extractvalue { i32, double, float } %struct.call, 0
  %v6 = extractvalue { i32, double, float } %struct.call, 1
  %v7 = extractvalue { i32, double, float } %struct.call, 2
  br label %b6

b3:                                               ; preds = %b1
  ret i32 0

b4:                                               ; preds = %b11
  ret i32 1

b5:                                               ; preds = %b11
  %v13 = add i32 %v0, 1
  br label %b1

b6:                                               ; preds = %b2
  br label %b7

b7:                                               ; preds = %b6
  %v8 = icmp ne i32 %v5, %v0
  br i1 %v8, label %b9, label %b8

b8:                                               ; preds = %b7
  %v9 = call i32 @c_check(i32 %v0, double %v6)
  %v10 = icmp ne i32 %v9, 0
  br label %b9

b9:                                               ; preds = %b8, %b7
  %v1 = phi i1 [ true, %b7 ], [ %v10, %b8 ]
  br i1 %v1, label %b11, label %b10

b10:                                              ; preds = %b9
  %v11 = call i32 @c_check32(i32 %v0, float %v7)
  %v12 = icmp ne i32 %v11, 0
  br label %b11

b11:                                              ; preds = %b10, %b9
  %v2 = phi i1 [ true, %b9 ], [ %v12, %b10 ]
  br i1 %v2, label %b4, label %b5
}

declare float @c_echo32(float)

declare float @c_pattern32(i32)

declare i32 @c_check32(i32, float)

declare double @c_echo(double)

declare double @c_pattern(i32)

declare i32 @c_count()

declare i32 @c_check(i32, double)
