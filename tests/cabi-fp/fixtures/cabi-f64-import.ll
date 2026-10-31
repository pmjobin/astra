; ModuleID = 'astra.scalar'
source_filename = "astra.scalar"

define internal fastcc double @astra.fn.0(double %p0) {
b0:
  %v1 = call double @c_echo(double %p0)
  ret double %v1
}

define internal fastcc i32 @astra.fn.1() {
b0:
  br label %b1

b1:                                               ; preds = %b10, %b0
  %v0 = phi i32 [ 0, %b0 ], [ %v13, %b10 ]
  %v2 = call i32 @c_count()
  %v3 = icmp slt i32 %v0, %v2
  br i1 %v3, label %b2, label %b3

b2:                                               ; preds = %b1
  %v4 = call double @c_pattern(i32 %v0)
  %v5 = call double @c_echo(double %v4)
  br label %b6

b3:                                               ; preds = %b1
  %v14 = call double @c_produce()
  %v15 = call i32 @c_check(i32 5, double %v14)
  ret i32 %v15

b4:                                               ; preds = %b8
  ret i32 1

b5:                                               ; preds = %b8
  call void @c_consume(double %v5)
  %v11 = call i32 @c_consumed(i32 %v0)
  %v12 = icmp ne i32 %v11, 0
  br i1 %v12, label %b9, label %b10

b6:                                               ; preds = %b2
  %v6 = call i32 @c_check(i32 %v0, double %v5)
  %v7 = icmp ne i32 %v6, 0
  br i1 %v7, label %b8, label %b7

b7:                                               ; preds = %b6
  %v8 = call fastcc double @astra.fn.0(double %v5)
  %v9 = call i32 @c_check(i32 %v0, double %v8)
  %v10 = icmp ne i32 %v9, 0
  br label %b8

b8:                                               ; preds = %b7, %b6
  %v1 = phi i1 [ true, %b6 ], [ %v10, %b7 ]
  br i1 %v1, label %b4, label %b5

b9:                                               ; preds = %b5
  ret i32 2

b10:                                              ; preds = %b5
  %v13 = add i32 %v0, 1
  br label %b1
}

declare double @c_echo(double)

declare double @c_pattern(i32)

declare i32 @c_count()

declare i32 @c_check(i32, double)

declare void @c_consume(double)

declare i32 @c_consumed(i32)

declare double @c_produce()
