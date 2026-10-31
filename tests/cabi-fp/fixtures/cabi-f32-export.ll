; ModuleID = 'astra.scalar'
source_filename = "astra.scalar"

define internal fastcc float @astra.fn.0(float %p0) {
b0:
  ret float %p0
}

define internal fastcc float @astra.fn.1(float %p0) {
b0:
  %v1 = call float @c_echo32(float %p0)
  ret float %v1
}

define internal fastcc void @astra.fn.2(float %p0) {
b0:
  call void @c_consume32(float %p0)
  ret void
}

define internal fastcc float @astra.fn.3() {
b0:
  %v0 = call float @c_produce32()
  ret float %v0
}

define internal fastcc i32 @astra.fn.4() {
b0:
  %v1 = call i32 @c_reverse_matrix32()
  %v2 = icmp ne i32 %v1, 0
  br i1 %v2, label %b1, label %b2

b1:                                               ; preds = %b0
  ret i32 1

b2:                                               ; preds = %b0
  br label %b3

b3:                                               ; preds = %b7, %b2
  %v0 = phi i32 [ 0, %b2 ], [ %v9, %b7 ]
  %v3 = call i32 @c_count32()
  %v4 = icmp slt i32 %v0, %v3
  br i1 %v4, label %b4, label %b5

b4:                                               ; preds = %b3
  %v5 = call float @c_pattern32(i32 %v0)
  %v6 = call float @c_chain32(float %v5)
  %v7 = call i32 @c_check32(i32 %v0, float %v6)
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

declare float @c_echo32(float)

declare void @c_consume32(float)

declare float @c_produce32()

declare float @c_pattern32(i32)

declare i32 @c_count32()

declare i32 @c_check32(i32, float)

declare float @c_chain32(float)

declare i32 @c_reverse_matrix32()

define float @astra_echo32(float %0) {
entry:
  %result = call fastcc float @astra.fn.0(float %0)
  ret float %result
}

define float @astra_bridge32(float %0) {
entry:
  %result = call fastcc float @astra.fn.1(float %0)
  ret float %result
}

define void @astra_consume32(float %0) {
entry:
  call fastcc void @astra.fn.2(float %0)
  ret void
}

define float @astra_produce32() {
entry:
  %result = call fastcc float @astra.fn.3()
  ret float %result
}
