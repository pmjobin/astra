; ModuleID = 'astra.scalar'
source_filename = "astra.scalar"

%astra.struct.1 = type { %astra.struct.0, %astra.struct.0 }
%astra.struct.0 = type { i32, i32 }

define internal fastcc i32 @astra.fn.0(ptr %p0, ptr %p1) {
b0:
  %memory0.base.base.null = icmp eq ptr %p0, null
  br i1 %memory0.base.base.null, label %memory0.base.base.trap, label %memory0.base.base.nonnull

memory0.base.base.trap:                           ; preds = %b0
  call void @llvm.trap()
  unreachable

memory0.base.base.nonnull:                        ; preds = %b0
  %memory0.base.field = getelementptr inbounds nuw %astra.struct.1, ptr %p0, i32 0, i32 0
  %memory0.field = getelementptr inbounds nuw %astra.struct.0, ptr %memory0.base.field, i32 0, i32 0
  store i32 40, ptr %memory0.field, align 4
  %memory1.base.base.null = icmp eq ptr %p1, null
  br i1 %memory1.base.base.null, label %memory1.base.base.trap, label %memory1.base.base.nonnull

memory1.base.base.trap:                           ; preds = %memory0.base.base.nonnull
  call void @llvm.trap()
  unreachable

memory1.base.base.nonnull:                        ; preds = %memory0.base.base.nonnull
  %memory1.base.field = getelementptr inbounds nuw %astra.struct.1, ptr %p1, i32 0, i32 0
  %memory1.field = getelementptr inbounds nuw %astra.struct.0, ptr %memory1.base.field, i32 0, i32 0
  %v2 = load i32, ptr %memory1.field, align 4
  %v3 = add i32 %v2, 2
  %memory2.base.base.null = icmp eq ptr %p1, null
  br i1 %memory2.base.base.null, label %memory2.base.base.trap, label %memory2.base.base.nonnull

memory2.base.base.trap:                           ; preds = %memory1.base.base.nonnull
  call void @llvm.trap()
  unreachable

memory2.base.base.nonnull:                        ; preds = %memory1.base.base.nonnull
  %memory2.base.field = getelementptr inbounds nuw %astra.struct.1, ptr %p1, i32 0, i32 0
  %memory2.field = getelementptr inbounds nuw %astra.struct.0, ptr %memory2.base.field, i32 0, i32 0
  store i32 %v3, ptr %memory2.field, align 4
  %memory3.base.base.null = icmp eq ptr %p0, null
  br i1 %memory3.base.base.null, label %memory3.base.base.trap, label %memory3.base.base.nonnull

memory3.base.base.trap:                           ; preds = %memory2.base.base.nonnull
  call void @llvm.trap()
  unreachable

memory3.base.base.nonnull:                        ; preds = %memory2.base.base.nonnull
  %memory3.base.field = getelementptr inbounds nuw %astra.struct.1, ptr %p0, i32 0, i32 1
  %memory3.field = getelementptr inbounds nuw %astra.struct.0, ptr %memory3.base.field, i32 0, i32 0
  store i32 7, ptr %memory3.field, align 4
  %memory4.base.base.null = icmp eq ptr %p1, null
  br i1 %memory4.base.base.null, label %memory4.base.base.trap, label %memory4.base.base.nonnull

memory4.base.base.trap:                           ; preds = %memory3.base.base.nonnull
  call void @llvm.trap()
  unreachable

memory4.base.base.nonnull:                        ; preds = %memory3.base.base.nonnull
  %memory4.base.field = getelementptr inbounds nuw %astra.struct.1, ptr %p1, i32 0, i32 0
  %memory4.field = getelementptr inbounds nuw %astra.struct.0, ptr %memory4.base.field, i32 0, i32 0
  %v4 = load i32, ptr %memory4.field, align 4
  %memory5.base.base.null = icmp eq ptr %p1, null
  br i1 %memory5.base.base.null, label %memory5.base.base.trap, label %memory5.base.base.nonnull

memory5.base.base.trap:                           ; preds = %memory4.base.base.nonnull
  call void @llvm.trap()
  unreachable

memory5.base.base.nonnull:                        ; preds = %memory4.base.base.nonnull
  %memory5.base.field = getelementptr inbounds nuw %astra.struct.1, ptr %p1, i32 0, i32 1
  %memory5.field = getelementptr inbounds nuw %astra.struct.0, ptr %memory5.base.field, i32 0, i32 0
  %v5 = load i32, ptr %memory5.field, align 4
  %v6 = add i32 %v4, %v5
  ret i32 %v6
}

define internal fastcc i32 @astra.fn.1() {
b0:
  %storage0 = alloca %astra.struct.1, align 8
  %memory0.base.field = getelementptr inbounds nuw %astra.struct.1, ptr %storage0, i32 0, i32 0
  %memory0.field = getelementptr inbounds nuw %astra.struct.0, ptr %memory0.base.field, i32 0, i32 0
  store i32 1, ptr %memory0.field, align 4
  %memory1.base.field = getelementptr inbounds nuw %astra.struct.1, ptr %storage0, i32 0, i32 0
  %memory1.field = getelementptr inbounds nuw %astra.struct.0, ptr %memory1.base.field, i32 0, i32 1
  store i32 2, ptr %memory1.field, align 4
  %memory2.base.field = getelementptr inbounds nuw %astra.struct.1, ptr %storage0, i32 0, i32 1
  %memory2.field = getelementptr inbounds nuw %astra.struct.0, ptr %memory2.base.field, i32 0, i32 0
  store i32 3, ptr %memory2.field, align 4
  %memory3.base.field = getelementptr inbounds nuw %astra.struct.1, ptr %storage0, i32 0, i32 1
  %memory3.field = getelementptr inbounds nuw %astra.struct.0, ptr %memory3.base.field, i32 0, i32 1
  store i32 4, ptr %memory3.field, align 4
  br label %b3

b1:                                               ; preds = %b14
  ret i32 1

b2:                                               ; preds = %b14
  ret i32 0

b3:                                               ; preds = %b0
  br label %b4

b4:                                               ; preds = %b3
  br label %b5

b5:                                               ; preds = %b4
  br label %b6

b6:                                               ; preds = %b5
  %v5 = call fastcc i32 @astra.fn.0(ptr %storage0, ptr %storage0)
  %v6 = icmp ne i32 %v5, 49
  br i1 %v6, label %b8, label %b7

b7:                                               ; preds = %b6
  %memory7.base.field = getelementptr inbounds nuw %astra.struct.1, ptr %storage0, i32 0, i32 0
  %memory7.field = getelementptr inbounds nuw %astra.struct.0, ptr %memory7.base.field, i32 0, i32 0
  %v7 = load i32, ptr %memory7.field, align 4
  %v8 = icmp ne i32 %v7, 42
  br label %b8

b8:                                               ; preds = %b7, %b6
  %v0 = phi i1 [ true, %b6 ], [ %v8, %b7 ]
  br i1 %v0, label %b10, label %b9

b9:                                               ; preds = %b8
  %memory6.base.field = getelementptr inbounds nuw %astra.struct.1, ptr %storage0, i32 0, i32 1
  %memory6.field = getelementptr inbounds nuw %astra.struct.0, ptr %memory6.base.field, i32 0, i32 0
  %v9 = load i32, ptr %memory6.field, align 4
  %v10 = icmp ne i32 %v9, 7
  br label %b10

b10:                                              ; preds = %b9, %b8
  %v1 = phi i1 [ true, %b8 ], [ %v10, %b9 ]
  br i1 %v1, label %b12, label %b11

b11:                                              ; preds = %b10
  %memory5.base.field = getelementptr inbounds nuw %astra.struct.1, ptr %storage0, i32 0, i32 0
  %memory5.field = getelementptr inbounds nuw %astra.struct.0, ptr %memory5.base.field, i32 0, i32 1
  %v11 = load i32, ptr %memory5.field, align 4
  %v12 = icmp ne i32 %v11, 2
  br label %b12

b12:                                              ; preds = %b11, %b10
  %v2 = phi i1 [ true, %b10 ], [ %v12, %b11 ]
  br i1 %v2, label %b14, label %b13

b13:                                              ; preds = %b12
  %memory4.base.field = getelementptr inbounds nuw %astra.struct.1, ptr %storage0, i32 0, i32 1
  %memory4.field = getelementptr inbounds nuw %astra.struct.0, ptr %memory4.base.field, i32 0, i32 1
  %v13 = load i32, ptr %memory4.field, align 4
  %v14 = icmp ne i32 %v13, 4
  br label %b14

b14:                                              ; preds = %b13, %b12
  %v3 = phi i1 [ true, %b12 ], [ %v14, %b13 ]
  br i1 %v3, label %b1, label %b2
}

; Function Attrs: cold noreturn nounwind memory(inaccessiblemem: write)
declare void @llvm.trap() #0

attributes #0 = { cold noreturn nounwind memory(inaccessiblemem: write) }
