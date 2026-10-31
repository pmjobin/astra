; ModuleID = 'astra.scalar'
source_filename = "astra.scalar"

%astra.struct.0 = type { i32, double }
%astra.struct.1 = type { %astra.struct.2, i32 }
%astra.struct.2 = type { double, double }

define internal fastcc i32 @astra.fn.0(ptr %p0, ptr %p1) {
b0:
  %memory0.base.null = icmp eq ptr %p0, null
  br i1 %memory0.base.null, label %memory0.base.trap, label %memory0.base.nonnull

memory0.base.trap:                                ; preds = %b0
  call void @llvm.trap()
  unreachable

memory0.base.nonnull:                             ; preds = %b0
  %memory0.field = getelementptr inbounds nuw %astra.struct.0, ptr %p0, i32 0, i32 0
  store i32 7, ptr %memory0.field, align 4
  %memory1.base.null = icmp eq ptr %p1, null
  br i1 %memory1.base.null, label %memory1.base.trap, label %memory1.base.nonnull

memory1.base.trap:                                ; preds = %memory0.base.nonnull
  call void @llvm.trap()
  unreachable

memory1.base.nonnull:                             ; preds = %memory0.base.nonnull
  %memory1.field = getelementptr inbounds nuw %astra.struct.0, ptr %p1, i32 0, i32 0
  store i32 42, ptr %memory1.field, align 4
  %memory2.base.null = icmp eq ptr %p0, null
  br i1 %memory2.base.null, label %memory2.base.trap, label %memory2.base.nonnull

memory2.base.trap:                                ; preds = %memory1.base.nonnull
  call void @llvm.trap()
  unreachable

memory2.base.nonnull:                             ; preds = %memory1.base.nonnull
  %memory2.field = getelementptr inbounds nuw %astra.struct.0, ptr %p0, i32 0, i32 0
  %v2 = load i32, ptr %memory2.field, align 4
  ret i32 %v2
}

define internal fastcc void @astra.fn.1(ptr %p0) {
b0:
  %memory0.base.base.null = icmp eq ptr %p0, null
  br i1 %memory0.base.base.null, label %memory0.base.base.trap, label %memory0.base.base.nonnull

memory0.base.base.trap:                           ; preds = %b0
  call void @llvm.trap()
  unreachable

memory0.base.base.nonnull:                        ; preds = %b0
  %memory0.base.field = getelementptr inbounds nuw %astra.struct.1, ptr %p0, i32 0, i32 0
  %memory0.field = getelementptr inbounds nuw %astra.struct.2, ptr %memory0.base.field, i32 0, i32 1
  store double 7.250000e+00, ptr %memory0.field, align 8
  %memory1.base.null = icmp eq ptr %p0, null
  br i1 %memory1.base.null, label %memory1.base.trap, label %memory1.base.nonnull

memory1.base.trap:                                ; preds = %memory0.base.base.nonnull
  call void @llvm.trap()
  unreachable

memory1.base.nonnull:                             ; preds = %memory0.base.base.nonnull
  %memory1.field = getelementptr inbounds nuw %astra.struct.1, ptr %p0, i32 0, i32 1
  store i32 9, ptr %memory1.field, align 4
  ret void
}

define internal fastcc i32 @astra.fn.2(i32 %p0) {
b0:
  %storage0 = alloca %astra.struct.0, align 8
  %memory0.field = getelementptr inbounds nuw %astra.struct.0, ptr %storage0, i32 0, i32 0
  store i32 2, ptr %memory0.field, align 4
  %memory1.field = getelementptr inbounds nuw %astra.struct.0, ptr %storage0, i32 0, i32 1
  store double 2.500000e+00, ptr %memory1.field, align 8
  %v2 = call fastcc i32 @astra.fn.0(ptr %storage0, ptr %storage0)
  %v3 = add i32 %p0, %v2
  ret i32 %v3
}

define internal fastcc i32 @astra.fn.3() {
b0:
  %storage0 = alloca %astra.struct.1, align 8
  %memory0.base.field = getelementptr inbounds nuw %astra.struct.1, ptr %storage0, i32 0, i32 0
  %memory0.field = getelementptr inbounds nuw %astra.struct.2, ptr %memory0.base.field, i32 0, i32 0
  store double 1.000000e+00, ptr %memory0.field, align 8
  %memory1.base.field = getelementptr inbounds nuw %astra.struct.1, ptr %storage0, i32 0, i32 0
  %memory1.field = getelementptr inbounds nuw %astra.struct.2, ptr %memory1.base.field, i32 0, i32 1
  store double 2.000000e+00, ptr %memory1.field, align 8
  %memory2.field = getelementptr inbounds nuw %astra.struct.1, ptr %storage0, i32 0, i32 1
  store i32 7, ptr %memory2.field, align 4
  call fastcc void @astra.fn.1(ptr %storage0)
  br label %b3

b1:                                               ; preds = %b11
  ret i32 1

b2:                                               ; preds = %b11
  ret i32 0

b3:                                               ; preds = %b0
  br label %b4

b4:                                               ; preds = %b3
  br label %b5

b5:                                               ; preds = %b4
  %memory3.base.field = getelementptr inbounds nuw %astra.struct.1, ptr %storage0, i32 0, i32 0
  %memory3.field = getelementptr inbounds nuw %astra.struct.2, ptr %memory3.base.field, i32 0, i32 0
  %v4 = load double, ptr %memory3.field, align 8
  %v5 = fcmp une double %v4, 1.000000e+00
  br i1 %v5, label %b7, label %b6

b6:                                               ; preds = %b5
  %memory5.base.field = getelementptr inbounds nuw %astra.struct.1, ptr %storage0, i32 0, i32 0
  %memory5.field = getelementptr inbounds nuw %astra.struct.2, ptr %memory5.base.field, i32 0, i32 1
  %v6 = load double, ptr %memory5.field, align 8
  %v7 = fcmp une double %v6, 7.250000e+00
  br label %b7

b7:                                               ; preds = %b6, %b5
  %v0 = phi i1 [ true, %b5 ], [ %v7, %b6 ]
  br i1 %v0, label %b9, label %b8

b8:                                               ; preds = %b7
  %memory4.field = getelementptr inbounds nuw %astra.struct.1, ptr %storage0, i32 0, i32 1
  %v8 = load i32, ptr %memory4.field, align 4
  %v9 = icmp ne i32 %v8, 9
  br label %b9

b9:                                               ; preds = %b8, %b7
  %v1 = phi i1 [ true, %b7 ], [ %v9, %b8 ]
  br i1 %v1, label %b11, label %b10

b10:                                              ; preds = %b9
  %v10 = call fastcc i32 @astra.fn.2(i32 7)
  %v11 = icmp ne i32 %v10, 49
  br label %b11

b11:                                              ; preds = %b10, %b9
  %v2 = phi i1 [ true, %b9 ], [ %v11, %b10 ]
  br i1 %v2, label %b1, label %b2
}

; Function Attrs: cold noreturn nounwind memory(inaccessiblemem: write)
declare void @llvm.trap() #0

attributes #0 = { cold noreturn nounwind memory(inaccessiblemem: write) }
