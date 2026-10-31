; ModuleID = 'astra.scalar'
source_filename = "astra.scalar"

define internal fastcc float @astra.fn.0(float %p0) {
b0:
  %v1 = call float @c_echo32(float %p0)
  ret float %v1
}

define internal fastcc i32 @astra.fn.1() {
b0:
  br label %b1

b1:                                               ; preds = %b10, %b0
  %v0 = phi i32 [ 0, %b0 ], [ %v13, %b10 ]
  %v2 = call i32 @c_count32()
  %v3 = icmp slt i32 %v0, %v2
  br i1 %v3, label %b2, label %b3

b2:                                               ; preds = %b1
  %v4 = call float @c_pattern32(i32 %v0)
  %v5 = call float @c_echo32(float %v4)
  br label %b6

b3:                                               ; preds = %b1
  %v14 = call float @c_pattern32(i32 0)
  %v15 = call float @c_pattern32(i32 1)
  %v16 = call float @c_pattern32(i32 2)
  %v17 = call float @c_pattern32(i32 3)
  %v18 = call float @c_pattern32(i32 4)
  %v19 = call float @c_pattern32(i32 5)
  %v20 = call float @c_pattern32(i32 6)
  %v21 = call float @c_pattern32(i32 7)
  %v22 = call float @c_pattern32(i32 8)
  %v23 = call float @c_pattern32(i32 9)
  %v24 = call float @c_many32(float %v14, float %v15, float %v16, float %v17, float %v18, float %v19, float %v20, float %v21, float %v22, float %v23)
  %v25 = call i32 @c_check32(i32 9, float %v24)
  %v26 = icmp ne i32 %v25, 0
  br i1 %v26, label %b11, label %b12

b4:                                               ; preds = %b8
  ret i32 1

b5:                                               ; preds = %b8
  call void @c_consume32(float %v5)
  %v11 = call i32 @c_consumed32(i32 %v0)
  %v12 = icmp ne i32 %v11, 0
  br i1 %v12, label %b9, label %b10

b6:                                               ; preds = %b2
  %v6 = call i32 @c_check32(i32 %v0, float %v5)
  %v7 = icmp ne i32 %v6, 0
  br i1 %v7, label %b8, label %b7

b7:                                               ; preds = %b6
  %v8 = call fastcc float @astra.fn.0(float %v5)
  %v9 = call i32 @c_check32(i32 %v0, float %v8)
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

b11:                                              ; preds = %b3
  ret i32 3

b12:                                              ; preds = %b3
  %v27 = call float @c_produce32()
  %v28 = call i32 @c_check32(i32 5, float %v27)
  ret i32 %v28
}

declare float @c_echo32(float)

declare float @c_pattern32(i32)

declare i32 @c_count32()

declare i32 @c_check32(i32, float)

declare void @c_consume32(float)

declare i32 @c_consumed32(i32)

declare float @c_produce32()

declare float @c_many32(float, float, float, float, float, float, float, float, float, float)
