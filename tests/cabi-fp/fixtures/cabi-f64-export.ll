; ModuleID = 'astra.scalar'
source_filename = "astra.scalar"

define internal fastcc double @astra.fn.0(double %p0) {
b0:
  ret double %p0
}

define internal fastcc double @astra.fn.1(double %p0) {
b0:
  %v1 = call double @c_echo(double %p0)
  ret double %v1
}

define internal fastcc void @astra.fn.2(double %p0) {
b0:
  call void @c_consume(double %p0)
  ret void
}

define internal fastcc double @astra.fn.3() {
b0:
  %v0 = call double @c_produce()
  ret double %v0
}

define internal fastcc i32 @astra.fn.4() {
b0:
  %v1 = call i32 @c_reverse_matrix()
  %v2 = icmp ne i32 %v1, 0
  br i1 %v2, label %b1, label %b2

b1:                                               ; preds = %b0
  ret i32 1

b2:                                               ; preds = %b0
  br label %b3

b3:                                               ; preds = %b7, %b2
  %v0 = phi i32 [ 0, %b2 ], [ %v9, %b7 ]
  %v3 = call i32 @c_count()
  %v4 = icmp slt i32 %v0, %v3
  br i1 %v4, label %b4, label %b5

b4:                                               ; preds = %b3
  %v5 = call double @c_pattern(i32 %v0)
  %v6 = call double @c_chain(double %v5)
  %v7 = call i32 @c_check(i32 %v0, double %v6)
  %v8 = icmp ne i32 %v7, 0
  br i1 %v8, label %b6, label %b7

b5:                                               ; preds = %b3
  ret i32 0

b6:                                               ; preds = %b4
  ret i32 2

b7:                                               ; preds = %b4
  %v9 = add i32 %v0, 1
  br label %b3
}

declare double @c_echo(double)

declare void @c_consume(double)

declare double @c_produce()

declare double @c_pattern(i32)

declare i32 @c_count()

declare i32 @c_check(i32, double)

declare double @c_chain(double)

declare i32 @c_reverse_matrix()

define double @astra_echo(double %0) {
entry:
  %result = call fastcc double @astra.fn.0(double %0)
  ret double %result
}

define double @astra_bridge(double %0) {
entry:
  %result = call fastcc double @astra.fn.1(double %0)
  ret double %result
}

define void @astra_consume(double %0) {
entry:
  call fastcc void @astra.fn.2(double %0)
  ret void
}

define double @astra_produce() {
entry:
  %result = call fastcc double @astra.fn.3()
  ret double %result
}
