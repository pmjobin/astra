; ModuleID = 'astra.scalar'
source_filename = "astra.scalar"

define internal fastcc i32 @astra.fn.0() {
b0:
  %storage0 = alloca [4 x i32], align 4
  %memory0.element = getelementptr [4 x i32], ptr %storage0, i64 0, i64 0
  store i32 10, ptr %memory0.element, align 4
  %memory1.element = getelementptr [4 x i32], ptr %storage0, i64 0, i64 1
  store i32 20, ptr %memory1.element, align 4
  %memory2.element = getelementptr [4 x i32], ptr %storage0, i64 0, i64 2
  store i32 30, ptr %memory2.element, align 4
  %memory3.element = getelementptr [4 x i32], ptr %storage0, i64 0, i64 3
  store i32 40, ptr %memory3.element, align 4
  br label %b3

b1:                                               ; preds = %b11
  ret i32 1

b2:                                               ; preds = %b11
  %memory5.element = getelementptr [4 x i32], ptr %storage0, i64 0, i64 2
  store i32 99, ptr %memory5.element, align 4
  %memory6.element = getelementptr [4 x i32], ptr %storage0, i64 0, i64 2
  %v11 = load i32, ptr %memory6.element, align 4
  %v12 = icmp ne i32 %v11, 99
  br i1 %v12, label %b12, label %b13

b3:                                               ; preds = %b0
  br label %b4

b4:                                               ; preds = %b3
  br label %b5

b5:                                               ; preds = %b4
  %memory4.element = getelementptr [4 x i32], ptr %storage0, i64 0, i64 0
  %v3 = load i32, ptr %memory4.element, align 4
  %v4 = icmp ne i32 %v3, 10
  br i1 %v4, label %b7, label %b6

b6:                                               ; preds = %b5
  %memory9.element = getelementptr [4 x i32], ptr %storage0, i64 0, i64 1
  %v5 = load i32, ptr %memory9.element, align 4
  %v6 = icmp ne i32 %v5, 20
  br label %b7

b7:                                               ; preds = %b6, %b5
  %v0 = phi i1 [ true, %b5 ], [ %v6, %b6 ]
  br i1 %v0, label %b9, label %b8

b8:                                               ; preds = %b7
  %memory8.element = getelementptr [4 x i32], ptr %storage0, i64 0, i64 2
  %v7 = load i32, ptr %memory8.element, align 4
  %v8 = icmp ne i32 %v7, 30
  br label %b9

b9:                                               ; preds = %b8, %b7
  %v1 = phi i1 [ true, %b7 ], [ %v8, %b8 ]
  br i1 %v1, label %b11, label %b10

b10:                                              ; preds = %b9
  %memory7.element = getelementptr [4 x i32], ptr %storage0, i64 0, i64 3
  %v9 = load i32, ptr %memory7.element, align 4
  %v10 = icmp ne i32 %v9, 40
  br label %b11

b11:                                              ; preds = %b10, %b9
  %v2 = phi i1 [ true, %b9 ], [ %v10, %b10 ]
  br i1 %v2, label %b1, label %b2

b12:                                              ; preds = %b2
  ret i32 2

b13:                                              ; preds = %b2
  ret i32 0
}
