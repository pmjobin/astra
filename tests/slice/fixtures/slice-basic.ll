; ModuleID = 'astra.scalar'
source_filename = "astra.scalar"

define internal fastcc i32 @astra.fn.0() {
b0:
  %storage0 = alloca [4 x i32], align 4
  %memory0.element = getelementptr [4 x i32], ptr %storage0, i64 0, i64 0
  store i32 1, ptr %memory0.element, align 4
  %memory1.element = getelementptr [4 x i32], ptr %storage0, i64 0, i64 1
  store i32 2, ptr %memory1.element, align 4
  %memory2.element = getelementptr [4 x i32], ptr %storage0, i64 0, i64 2
  store i32 3, ptr %memory2.element, align 4
  %memory3.element = getelementptr [4 x i32], ptr %storage0, i64 0, i64 3
  store i32 4, ptr %memory3.element, align 4
  %v3.element = getelementptr [4 x i32], ptr %storage0, i64 0, i64 0
  %v3.with.base = insertvalue { ptr, i32 } zeroinitializer, ptr %v3.element, 0
  %v3 = insertvalue { ptr, i32 } %v3.with.base, i32 4, 1
  br label %b3

b1:                                               ; preds = %b5
  ret i32 1

b2:                                               ; preds = %b5
  %slice.bounds4.length = extractvalue { ptr, i32 } %v3, 1
  %slice.bounds4.length.math = zext i32 %slice.bounds4.length to i64
  %slice.bounds4.oversized = icmp sge i64 1, %slice.bounds4.length.math
  %slice.bounds4.invalid = or i1 false, %slice.bounds4.oversized
  br i1 %slice.bounds4.invalid, label %slice.bounds4.trap, label %slice.bounds4.valid

b3:                                               ; preds = %b0
  %v4 = extractvalue { ptr, i32 } %v3, 1
  %v5 = icmp ne i32 %v4, 4
  br i1 %v5, label %b5, label %b4

b4:                                               ; preds = %b3
  br label %b5

b5:                                               ; preds = %b4, %b3
  %v0 = phi i1 [ true, %b3 ], [ false, %b4 ]
  br i1 %v0, label %b1, label %b2

b6:                                               ; preds = %b10
  ret i32 2

b7:                                               ; preds = %b10
  %memory8.element = getelementptr [4 x i32], ptr %storage0, i64 0, i64 2
  store i32 12, ptr %memory8.element, align 4
  %v13.element = getelementptr [4 x i32], ptr %storage0, i64 0, i64 0
  %v13.with.base = insertvalue { ptr, i32 } zeroinitializer, ptr %v13.element, 0
  %v13 = insertvalue { ptr, i32 } %v13.with.base, i32 4, 1
  %slice.bounds9.length = extractvalue { ptr, i32 } %v13, 1
  %slice.bounds9.length.math = zext i32 %slice.bounds9.length to i64
  %slice.bounds9.oversized = icmp sge i64 2, %slice.bounds9.length.math
  %slice.bounds9.invalid = or i1 false, %slice.bounds9.oversized
  br i1 %slice.bounds9.invalid, label %slice.bounds9.trap, label %slice.bounds9.valid

b8:                                               ; preds = %slice.bounds4.valid
  %slice.bounds6.length = extractvalue { ptr, i32 } %v3, 1
  %slice.bounds6.length.math = zext i32 %slice.bounds6.length to i64
  %slice.bounds6.oversized = icmp sge i64 1, %slice.bounds6.length.math
  %slice.bounds6.invalid = or i1 false, %slice.bounds6.oversized
  br i1 %slice.bounds6.invalid, label %slice.bounds6.trap, label %slice.bounds6.valid

b9:                                               ; preds = %slice.bounds6.valid
  %memory18.element = getelementptr [4 x i32], ptr %storage0, i64 0, i64 1
  %v11 = load i32, ptr %memory18.element, align 4
  %v12 = icmp ne i32 %v11, 42
  br label %b10

b10:                                              ; preds = %b9, %slice.bounds6.valid
  %v1 = phi i1 [ true, %slice.bounds6.valid ], [ %v12, %b9 ]
  br i1 %v1, label %b6, label %b7

b11:                                              ; preds = %slice.bounds9.valid
  ret i32 3

b12:                                              ; preds = %slice.bounds9.valid
  %v17.element = getelementptr [4 x i32], ptr %storage0, i64 0, i64 0
  %v17.with.base = insertvalue { ptr, i32 } zeroinitializer, ptr %v17.element, 0
  %v17 = insertvalue { ptr, i32 } %v17.with.base, i32 4, 1
  %slice.bounds11.length = extractvalue { ptr, i32 } %v17, 1
  %slice.bounds11.length.math = zext i32 %slice.bounds11.length to i64
  %slice.bounds11.oversized = icmp sge i64 2, %slice.bounds11.length.math
  %slice.bounds11.invalid = or i1 false, %slice.bounds11.oversized
  br i1 %slice.bounds11.invalid, label %slice.bounds11.trap, label %slice.bounds11.valid

b13:                                              ; preds = %slice.bounds11.valid
  ret i32 4

b14:                                              ; preds = %slice.bounds11.valid
  br label %b15

b15:                                              ; preds = %b19, %b14
  %v2 = phi i32 [ 0, %b14 ], [ %v28, %b19 ]
  %v21 = extractvalue { ptr, i32 } %v3, 1
  %v22 = icmp slt i32 %v2, %v21
  br i1 %v22, label %b16, label %b17

b16:                                              ; preds = %b15
  %slice.bounds14.length = extractvalue { ptr, i32 } %v3, 1
  %slice.bounds14.index.math = sext i32 %v2 to i64
  %slice.bounds14.length.math = zext i32 %slice.bounds14.length to i64
  %slice.bounds14.negative = icmp slt i64 %slice.bounds14.index.math, 0
  %slice.bounds14.oversized = icmp sge i64 %slice.bounds14.index.math, %slice.bounds14.length.math
  %slice.bounds14.invalid = or i1 %slice.bounds14.negative, %slice.bounds14.oversized
  br i1 %slice.bounds14.invalid, label %slice.bounds14.trap, label %slice.bounds14.valid

b17:                                              ; preds = %b15
  ret i32 0

b18:                                              ; preds = %bounds16.valid
  ret i32 5

b19:                                              ; preds = %bounds16.valid
  %v28 = add i32 %v2, 1
  br label %b15

slice.bounds4.trap:                               ; preds = %b2
  call void @llvm.trap()
  unreachable

slice.bounds4.valid:                              ; preds = %b2
  %memory5.base = extractvalue { ptr, i32 } %v3, 0
  %memory5.element = getelementptr i32, ptr %memory5.base, i64 1
  store i32 42, ptr %memory5.element, align 4
  br label %b8

slice.bounds6.trap:                               ; preds = %b8
  call void @llvm.trap()
  unreachable

slice.bounds6.valid:                              ; preds = %b8
  %memory7.base = extractvalue { ptr, i32 } %v3, 0
  %memory7.element = getelementptr i32, ptr %memory7.base, i64 1
  %v9 = load i32, ptr %memory7.element, align 4
  %v10 = icmp ne i32 %v9, 42
  br i1 %v10, label %b10, label %b9

slice.bounds9.trap:                               ; preds = %b7
  call void @llvm.trap()
  unreachable

slice.bounds9.valid:                              ; preds = %b7
  %memory10.base = extractvalue { ptr, i32 } %v13, 0
  %memory10.element = getelementptr i32, ptr %memory10.base, i64 2
  %v15 = load i32, ptr %memory10.element, align 4
  %v16 = icmp ne i32 %v15, 12
  br i1 %v16, label %b11, label %b12

slice.bounds11.trap:                              ; preds = %b12
  call void @llvm.trap()
  unreachable

slice.bounds11.valid:                             ; preds = %b12
  %memory12.base = extractvalue { ptr, i32 } %v17, 0
  %memory12.element = getelementptr i32, ptr %memory12.base, i64 2
  store i32 14, ptr %memory12.element, align 4
  %memory13.element = getelementptr [4 x i32], ptr %storage0, i64 0, i64 2
  %v19 = load i32, ptr %memory13.element, align 4
  %v20 = icmp ne i32 %v19, 14
  br i1 %v20, label %b13, label %b14

slice.bounds14.trap:                              ; preds = %b16
  call void @llvm.trap()
  unreachable

slice.bounds14.valid:                             ; preds = %b16
  %memory15.base = extractvalue { ptr, i32 } %v3, 0
  %memory15.ordinal = zext i32 %v2 to i64
  %memory15.element = getelementptr i32, ptr %memory15.base, i64 %memory15.ordinal
  %v24 = load i32, ptr %memory15.element, align 4
  %bounds16.oversized = icmp sge i32 %v2, 4
  %bounds16.negative = icmp slt i32 %v2, 0
  %bounds16.invalid = or i1 %bounds16.oversized, %bounds16.negative
  br i1 %bounds16.invalid, label %bounds16.trap, label %bounds16.valid

bounds16.trap:                                    ; preds = %slice.bounds14.valid
  call void @llvm.trap()
  unreachable

bounds16.valid:                                   ; preds = %slice.bounds14.valid
  %memory17.ordinal = zext i32 %v2 to i64
  %memory17.element = getelementptr [4 x i32], ptr %storage0, i64 0, i64 %memory17.ordinal
  %v26 = load i32, ptr %memory17.element, align 4
  %v27 = icmp ne i32 %v24, %v26
  br i1 %v27, label %b18, label %b19
}

; Function Attrs: cold noreturn nounwind memory(inaccessiblemem: write)
declare void @llvm.trap() #0

attributes #0 = { cold noreturn nounwind memory(inaccessiblemem: write) }
