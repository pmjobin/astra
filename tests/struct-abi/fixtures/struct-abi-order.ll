; ModuleID = 'astra.scalar'
source_filename = "astra.scalar"

%astra.struct.0 = type { i32, double }

define internal fastcc i32 @astra.fn.0(ptr %p0) {
b0:
  %memory0.null = icmp eq ptr %p0, null
  br i1 %memory0.null, label %memory0.trap, label %memory0.nonnull

memory0.trap:                                     ; preds = %b0
  call void @llvm.trap()
  unreachable

memory0.nonnull:                                  ; preds = %b0
  %memory0.field = getelementptr inbounds nuw %astra.struct.0, ptr %p0, i32 0, i32 0
  %v1 = load i32, ptr %memory0.field, align 4
  %v2 = add i32 %v1, 10
  %memory1.null = icmp eq ptr %p0, null
  br i1 %memory1.null, label %memory1.trap, label %memory1.nonnull

memory1.trap:                                     ; preds = %memory0.nonnull
  call void @llvm.trap()
  unreachable

memory1.nonnull:                                  ; preds = %memory0.nonnull
  %memory1.field = getelementptr inbounds nuw %astra.struct.0, ptr %p0, i32 0, i32 0
  store i32 %v2, ptr %memory1.field, align 4
  %memory2.null = icmp eq ptr %p0, null
  br i1 %memory2.null, label %memory2.trap, label %memory2.nonnull

memory2.trap:                                     ; preds = %memory1.nonnull
  call void @llvm.trap()
  unreachable

memory2.nonnull:                                  ; preds = %memory1.nonnull
  %memory2.field = getelementptr inbounds nuw %astra.struct.0, ptr %p0, i32 0, i32 1
  %v3 = load double, ptr %memory2.field, align 8
  %v4 = fadd double %v3, 1.000000e+01
  %memory3.null = icmp eq ptr %p0, null
  br i1 %memory3.null, label %memory3.trap, label %memory3.nonnull

memory3.trap:                                     ; preds = %memory2.nonnull
  call void @llvm.trap()
  unreachable

memory3.nonnull:                                  ; preds = %memory2.nonnull
  %memory3.field = getelementptr inbounds nuw %astra.struct.0, ptr %p0, i32 0, i32 1
  store double %v4, ptr %memory3.field, align 8
  %memory4.null = icmp eq ptr %p0, null
  br i1 %memory4.null, label %memory4.trap, label %memory4.nonnull

memory4.trap:                                     ; preds = %memory3.nonnull
  call void @llvm.trap()
  unreachable

memory4.nonnull:                                  ; preds = %memory3.nonnull
  %memory4.field = getelementptr inbounds nuw %astra.struct.0, ptr %p0, i32 0, i32 0
  %v5 = load i32, ptr %memory4.field, align 4
  ret i32 %v5
}

define internal fastcc { i32, double } @astra.fn.1(ptr %p0) {
b0:
  %memory0.null = icmp eq ptr %p0, null
  br i1 %memory0.null, label %memory0.trap, label %memory0.nonnull

memory0.trap:                                     ; preds = %b0
  call void @llvm.trap()
  unreachable

memory0.nonnull:                                  ; preds = %b0
  %memory0.field = getelementptr inbounds nuw %astra.struct.0, ptr %p0, i32 0, i32 0
  %v1 = load i32, ptr %memory0.field, align 4
  %v2 = add i32 %v1, 10
  %memory1.null = icmp eq ptr %p0, null
  br i1 %memory1.null, label %memory1.trap, label %memory1.nonnull

memory1.trap:                                     ; preds = %memory0.nonnull
  call void @llvm.trap()
  unreachable

memory1.nonnull:                                  ; preds = %memory0.nonnull
  %memory1.field = getelementptr inbounds nuw %astra.struct.0, ptr %p0, i32 0, i32 0
  store i32 %v2, ptr %memory1.field, align 4
  %memory2.null = icmp eq ptr %p0, null
  br i1 %memory2.null, label %memory2.trap, label %memory2.nonnull

memory2.trap:                                     ; preds = %memory1.nonnull
  call void @llvm.trap()
  unreachable

memory2.nonnull:                                  ; preds = %memory1.nonnull
  %memory2.field = getelementptr inbounds nuw %astra.struct.0, ptr %p0, i32 0, i32 1
  %v3 = load double, ptr %memory2.field, align 8
  %v4 = fadd double %v3, 1.000000e+01
  %memory3.null = icmp eq ptr %p0, null
  br i1 %memory3.null, label %memory3.trap, label %memory3.nonnull

memory3.trap:                                     ; preds = %memory2.nonnull
  call void @llvm.trap()
  unreachable

memory3.nonnull:                                  ; preds = %memory2.nonnull
  %memory3.field = getelementptr inbounds nuw %astra.struct.0, ptr %p0, i32 0, i32 1
  store double %v4, ptr %memory3.field, align 8
  %validate4.null = icmp eq ptr %p0, null
  br i1 %validate4.null, label %validate4.trap, label %validate4.nonnull

validate4.trap:                                   ; preds = %memory3.nonnull
  call void @llvm.trap()
  unreachable

validate4.nonnull:                                ; preds = %memory3.nonnull
  %memory5.base.null = icmp eq ptr %p0, null
  br i1 %memory5.base.null, label %memory5.base.trap, label %memory5.base.nonnull

memory5.base.trap:                                ; preds = %validate4.nonnull
  call void @llvm.trap()
  unreachable

memory5.base.nonnull:                             ; preds = %validate4.nonnull
  %memory5.field = getelementptr inbounds nuw %astra.struct.0, ptr %p0, i32 0, i32 0
  %v5 = load i32, ptr %memory5.field, align 4
  %memory6.base.null = icmp eq ptr %p0, null
  br i1 %memory6.base.null, label %memory6.base.trap, label %memory6.base.nonnull

memory6.base.trap:                                ; preds = %memory5.base.nonnull
  call void @llvm.trap()
  unreachable

memory6.base.nonnull:                             ; preds = %memory5.base.nonnull
  %memory6.field = getelementptr inbounds nuw %astra.struct.0, ptr %p0, i32 0, i32 1
  %v6 = load double, ptr %memory6.field, align 8
  %struct.return.0 = insertvalue { i32, double } zeroinitializer, i32 %v5, 0
  %struct.return.1 = insertvalue { i32, double } %struct.return.0, double %v6, 1
  ret { i32, double } %struct.return.1
}

define internal fastcc i32 @astra.fn.2(i32 %p0, double %p1, i32 %p2, i32 %p3, double %p4, double %p5) {
b0:
  br label %b3

b1:                                               ; preds = %b17
  ret i32 1

b2:                                               ; preds = %b17
  ret i32 0

b3:                                               ; preds = %b0
  br label %b4

b4:                                               ; preds = %b3
  br label %b5

b5:                                               ; preds = %b4
  br label %b6

b6:                                               ; preds = %b5
  br label %b7

b7:                                               ; preds = %b6
  %v11 = icmp ne i32 %p0, 7
  br i1 %v11, label %b9, label %b8

b8:                                               ; preds = %b7
  %v12 = fcmp une double %p1, 3.500000e+00
  br label %b9

b9:                                               ; preds = %b8, %b7
  %v6 = phi i1 [ true, %b7 ], [ %v12, %b8 ]
  br i1 %v6, label %b11, label %b10

b10:                                              ; preds = %b9
  %v13 = icmp ne i32 %p2, 17
  br label %b11

b11:                                              ; preds = %b10, %b9
  %v7 = phi i1 [ true, %b9 ], [ %v13, %b10 ]
  br i1 %v7, label %b13, label %b12

b12:                                              ; preds = %b11
  %v14 = icmp ne i32 %p3, 27
  br label %b13

b13:                                              ; preds = %b12, %b11
  %v8 = phi i1 [ true, %b11 ], [ %v14, %b12 ]
  br i1 %v8, label %b15, label %b14

b14:                                              ; preds = %b13
  %v15 = fcmp une double %p4, 2.350000e+01
  br label %b15

b15:                                              ; preds = %b14, %b13
  %v9 = phi i1 [ true, %b13 ], [ %v15, %b14 ]
  br i1 %v9, label %b17, label %b16

b16:                                              ; preds = %b15
  %v16 = fcmp une double %p5, 2.350000e+01
  br label %b17

b17:                                              ; preds = %b16, %b15
  %v10 = phi i1 [ true, %b15 ], [ %v16, %b16 ]
  br i1 %v10, label %b1, label %b2
}

define internal fastcc i32 @astra.fn.3(i32 %p0, i32 %p1, double %p2) {
b0:
  br label %b3

b1:                                               ; preds = %b5
  ret i32 2

b2:                                               ; preds = %b5
  ret i32 0

b3:                                               ; preds = %b0
  %v4 = icmp ne i32 %p0, 7
  br i1 %v4, label %b5, label %b4

b4:                                               ; preds = %b3
  %v5 = icmp ne i32 %p1, 17
  br label %b5

b5:                                               ; preds = %b4, %b3
  %v3 = phi i1 [ true, %b3 ], [ %v5, %b4 ]
  br i1 %v3, label %b1, label %b2
}

define internal fastcc i32 @astra.fn.4() {
b0:
  %storage0 = alloca %astra.struct.0, align 8
  %memory0.field = getelementptr inbounds nuw %astra.struct.0, ptr %storage0, i32 0, i32 0
  store i32 7, ptr %memory0.field, align 4
  %memory1.field = getelementptr inbounds nuw %astra.struct.0, ptr %storage0, i32 0, i32 1
  store double 3.500000e+00, ptr %memory1.field, align 8
  %memory2.field = getelementptr inbounds nuw %astra.struct.0, ptr %storage0, i32 0, i32 0
  %v2 = load i32, ptr %memory2.field, align 4
  %memory3.field = getelementptr inbounds nuw %astra.struct.0, ptr %storage0, i32 0, i32 1
  %v3 = load double, ptr %memory3.field, align 8
  %v5 = call fastcc i32 @astra.fn.0(ptr %storage0)
  %struct.call = call fastcc { i32, double } @astra.fn.1(ptr %storage0)
  %v7 = extractvalue { i32, double } %struct.call, 0
  %v8 = extractvalue { i32, double } %struct.call, 1
  %memory4.field = getelementptr inbounds nuw %astra.struct.0, ptr %storage0, i32 0, i32 1
  %v9 = load double, ptr %memory4.field, align 8
  %v10 = call fastcc i32 @astra.fn.2(i32 %v2, double %v3, i32 %v5, i32 %v7, double %v8, double %v9)
  br label %b3

b1:                                               ; preds = %b8
  ret i32 3

b2:                                               ; preds = %b8
  %memory5.field = getelementptr inbounds nuw %astra.struct.0, ptr %storage0, i32 0, i32 0
  store i32 7, ptr %memory5.field, align 4
  %memory6.field = getelementptr inbounds nuw %astra.struct.0, ptr %storage0, i32 0, i32 0
  %v16 = load i32, ptr %memory6.field, align 4
  %struct.call1 = call fastcc { i32, double } @astra.fn.1(ptr %storage0)
  %v18 = extractvalue { i32, double } %struct.call1, 0
  %v19 = extractvalue { i32, double } %struct.call1, 1
  %v20 = call fastcc i32 @astra.fn.3(i32 %v16, i32 %v18, double %v19)
  ret i32 %v20

b3:                                               ; preds = %b0
  br label %b4

b4:                                               ; preds = %b3
  %v11 = icmp ne i32 %v10, 0
  br i1 %v11, label %b6, label %b5

b5:                                               ; preds = %b4
  %memory8.field = getelementptr inbounds nuw %astra.struct.0, ptr %storage0, i32 0, i32 0
  %v12 = load i32, ptr %memory8.field, align 4
  %v13 = icmp ne i32 %v12, 27
  br label %b6

b6:                                               ; preds = %b5, %b4
  %v0 = phi i1 [ true, %b4 ], [ %v13, %b5 ]
  br i1 %v0, label %b8, label %b7

b7:                                               ; preds = %b6
  %memory7.field = getelementptr inbounds nuw %astra.struct.0, ptr %storage0, i32 0, i32 1
  %v14 = load double, ptr %memory7.field, align 8
  %v15 = fcmp une double %v14, 2.350000e+01
  br label %b8

b8:                                               ; preds = %b7, %b6
  %v1 = phi i1 [ true, %b6 ], [ %v15, %b7 ]
  br i1 %v1, label %b1, label %b2
}

; Function Attrs: cold noreturn nounwind memory(inaccessiblemem: write)
declare void @llvm.trap() #0

attributes #0 = { cold noreturn nounwind memory(inaccessiblemem: write) }
