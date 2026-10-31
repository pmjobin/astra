; ModuleID = 'astra.scalar'
source_filename = "astra.scalar"

%astra.struct.0 = type { i32, i32 }

define internal fastcc void @astra.fn.0(ptr %p0, i32 %p1) {
b0:
  %memory0.null = icmp eq ptr %p0, null
  br i1 %memory0.null, label %memory0.trap, label %memory0.nonnull

memory0.trap:                                     ; preds = %b0
  call void @llvm.trap()
  unreachable

memory0.nonnull:                                  ; preds = %b0
  %memory0.field = getelementptr inbounds nuw %astra.struct.0, ptr %p0, i32 0, i32 0
  store i32 %p1, ptr %memory0.field, align 4
  ret void
}

define internal fastcc i32 @astra.fn.1(ptr %p0) {
b0:
  br label %b3

b1:                                               ; preds = %b5
  ret i32 -1

b2:                                               ; preds = %b5
  br label %b8

b3:                                               ; preds = %b0
  br i1 false, label %b5, label %b4

b4:                                               ; preds = %b3
  br label %b5

b5:                                               ; preds = %b4, %b3
  %v1 = phi i1 [ true, %b3 ], [ false, %b4 ]
  br i1 %v1, label %b1, label %b2

b6:                                               ; preds = %b10
  ret i32 -2

b7:                                               ; preds = %b10
  %memory0.null = icmp eq ptr %p0, null
  br i1 %memory0.null, label %memory0.trap, label %memory0.nonnull

b8:                                               ; preds = %b2
  br i1 false, label %b10, label %b9

b9:                                               ; preds = %b8
  %v6 = icmp ne ptr %p0, %p0
  br label %b10

b10:                                              ; preds = %b9, %b8
  %v2 = phi i1 [ true, %b8 ], [ %v6, %b9 ]
  br i1 %v2, label %b6, label %b7

memory0.trap:                                     ; preds = %b7
  call void @llvm.trap()
  unreachable

memory0.nonnull:                                  ; preds = %b7
  %memory0.field = getelementptr inbounds nuw %astra.struct.0, ptr %p0, i32 0, i32 0
  %v7 = load i32, ptr %memory0.field, align 4
  ret i32 %v7
}

define internal fastcc i32 @astra.fn.2() {
b0:
  %storage0 = alloca %astra.struct.0, align 8
  %memory0.field = getelementptr inbounds nuw %astra.struct.0, ptr %storage0, i32 0, i32 0
  store i32 1, ptr %memory0.field, align 4
  %memory1.field = getelementptr inbounds nuw %astra.struct.0, ptr %storage0, i32 0, i32 1
  store i32 2, ptr %memory1.field, align 4
  %memory2.field = getelementptr inbounds nuw %astra.struct.0, ptr %storage0, i32 0, i32 0
  %v1 = load i32, ptr %memory2.field, align 4
  call fastcc void @astra.fn.0(ptr %storage0, i32 42)
  %memory3.field = getelementptr inbounds nuw %astra.struct.0, ptr %storage0, i32 0, i32 0
  %v3 = load i32, ptr %memory3.field, align 4
  %v4 = icmp ne i32 %v1, 1
  br i1 %v4, label %b1, label %b2

b1:                                               ; preds = %b0
  ret i32 1

b2:                                               ; preds = %b0
  br label %b5

b3:                                               ; preds = %b7
  ret i32 2

b4:                                               ; preds = %b7
  %v9 = call fastcc i32 @astra.fn.1(ptr %storage0)
  %v10 = icmp ne i32 %v9, 42
  br i1 %v10, label %b8, label %b9

b5:                                               ; preds = %b2
  %v5 = icmp ne i32 %v3, 42
  br i1 %v5, label %b7, label %b6

b6:                                               ; preds = %b5
  %memory4.field = getelementptr inbounds nuw %astra.struct.0, ptr %storage0, i32 0, i32 1
  %v6 = load i32, ptr %memory4.field, align 4
  %v7 = icmp ne i32 %v6, 2
  br label %b7

b7:                                               ; preds = %b6, %b5
  %v0 = phi i1 [ true, %b5 ], [ %v7, %b6 ]
  br i1 %v0, label %b3, label %b4

b8:                                               ; preds = %b4
  ret i32 3

b9:                                               ; preds = %b4
  ret i32 0
}

; Function Attrs: cold noreturn nounwind memory(inaccessiblemem: write)
declare void @llvm.trap() #0

attributes #0 = { cold noreturn nounwind memory(inaccessiblemem: write) }
