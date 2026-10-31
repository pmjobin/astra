; ModuleID = 'astra.scalar'
source_filename = "astra.scalar"

define internal fastcc i32 @astra.fn.0(ptr %p0.base, i32 %p0.length) {
b0:
  %p0.with.base = insertvalue { ptr, i32 } zeroinitializer, ptr %p0.base, 0
  %p0 = insertvalue { ptr, i32 } %p0.with.base, i32 %p0.length, 1
  br label %b1

b1:                                               ; preds = %slice.bounds0.valid, %b0
  %v1 = phi i32 [ 0, %b0 ], [ %v7, %slice.bounds0.valid ]
  %v2 = phi i32 [ 0, %b0 ], [ %v8, %slice.bounds0.valid ]
  %v3 = extractvalue { ptr, i32 } %p0, 1
  %v4 = icmp slt i32 %v2, %v3
  br i1 %v4, label %b2, label %b3

b2:                                               ; preds = %b1
  %slice.bounds0.length = extractvalue { ptr, i32 } %p0, 1
  %slice.bounds0.index.math = sext i32 %v2 to i64
  %slice.bounds0.length.math = zext i32 %slice.bounds0.length to i64
  %slice.bounds0.negative = icmp slt i64 %slice.bounds0.index.math, 0
  %slice.bounds0.oversized = icmp sge i64 %slice.bounds0.index.math, %slice.bounds0.length.math
  %slice.bounds0.invalid = or i1 %slice.bounds0.negative, %slice.bounds0.oversized
  br i1 %slice.bounds0.invalid, label %slice.bounds0.trap, label %slice.bounds0.valid

b3:                                               ; preds = %b1
  ret i32 %v1

slice.bounds0.trap:                               ; preds = %b2
  call void @llvm.trap()
  unreachable

slice.bounds0.valid:                              ; preds = %b2
  %memory1.base = extractvalue { ptr, i32 } %p0, 0
  %memory1.ordinal = zext i32 %v2 to i64
  %memory1.element = getelementptr i32, ptr %memory1.base, i64 %memory1.ordinal
  %v6 = load i32, ptr %memory1.element, align 4
  %v7 = add i32 %v1, %v6
  %v8 = add i32 %v2, 1
  br label %b1
}

define internal fastcc i32 @astra.fn.1() {
b0:
  %storage0 = alloca [4 x i32], align 4
  %storage1 = alloca [8 x i32], align 4
  %memory0.element = getelementptr [4 x i32], ptr %storage0, i64 0, i64 0
  store i32 1, ptr %memory0.element, align 4
  %memory1.element = getelementptr [4 x i32], ptr %storage0, i64 0, i64 1
  store i32 2, ptr %memory1.element, align 4
  %memory2.element = getelementptr [4 x i32], ptr %storage0, i64 0, i64 2
  store i32 3, ptr %memory2.element, align 4
  %memory3.element = getelementptr [4 x i32], ptr %storage0, i64 0, i64 3
  store i32 4, ptr %memory3.element, align 4
  %memory4.element = getelementptr [8 x i32], ptr %storage1, i64 0, i64 0
  store i32 1, ptr %memory4.element, align 4
  %memory5.element = getelementptr [8 x i32], ptr %storage1, i64 0, i64 1
  store i32 2, ptr %memory5.element, align 4
  %memory6.element = getelementptr [8 x i32], ptr %storage1, i64 0, i64 2
  store i32 3, ptr %memory6.element, align 4
  %memory7.element = getelementptr [8 x i32], ptr %storage1, i64 0, i64 3
  store i32 4, ptr %memory7.element, align 4
  %memory8.element = getelementptr [8 x i32], ptr %storage1, i64 0, i64 4
  store i32 5, ptr %memory8.element, align 4
  %memory9.element = getelementptr [8 x i32], ptr %storage1, i64 0, i64 5
  store i32 6, ptr %memory9.element, align 4
  %memory10.element = getelementptr [8 x i32], ptr %storage1, i64 0, i64 6
  store i32 7, ptr %memory10.element, align 4
  %memory11.element = getelementptr [8 x i32], ptr %storage1, i64 0, i64 7
  store i32 8, ptr %memory11.element, align 4
  %v0.element = getelementptr [4 x i32], ptr %storage0, i64 0, i64 0
  %v0.with.base = insertvalue { ptr, i32 } zeroinitializer, ptr %v0.element, 0
  %v0 = insertvalue { ptr, i32 } %v0.with.base, i32 4, 1
  %arg0.base = extractvalue { ptr, i32 } %v0, 0
  %arg0.length = extractvalue { ptr, i32 } %v0, 1
  %v1 = call fastcc i32 @astra.fn.0(ptr %arg0.base, i32 %arg0.length)
  %v2.element = getelementptr [8 x i32], ptr %storage1, i64 0, i64 0
  %v2.with.base = insertvalue { ptr, i32 } zeroinitializer, ptr %v2.element, 0
  %v2 = insertvalue { ptr, i32 } %v2.with.base, i32 8, 1
  %arg0.base1 = extractvalue { ptr, i32 } %v2, 0
  %arg0.length2 = extractvalue { ptr, i32 } %v2, 1
  %v3 = call fastcc i32 @astra.fn.0(ptr %arg0.base1, i32 %arg0.length2)
  %v4 = add i32 %v1, %v3
  ret i32 %v4
}

; Function Attrs: cold noreturn nounwind memory(inaccessiblemem: write)
declare void @llvm.trap() #0

attributes #0 = { cold noreturn nounwind memory(inaccessiblemem: write) }
