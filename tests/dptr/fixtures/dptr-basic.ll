; ModuleID = 'astra.scalar'
source_filename = "astra.scalar"

define internal fastcc i32 @astra.fn.0(ptr %p0) {
b0:
  %memory0.null = icmp eq ptr %p0, null
  br i1 %memory0.null, label %memory0.trap, label %memory0.nonnull

memory0.trap:                                     ; preds = %b0
  call void @llvm.trap()
  unreachable

memory0.nonnull:                                  ; preds = %b0
  %v1 = load i32, ptr %p0, align 4
  ret i32 %v1
}

define internal fastcc void @astra.fn.1(ptr %p0, i32 %p1) {
b0:
  %memory0.null = icmp eq ptr %p0, null
  br i1 %memory0.null, label %memory0.trap, label %memory0.nonnull

memory0.trap:                                     ; preds = %b0
  call void @llvm.trap()
  unreachable

memory0.nonnull:                                  ; preds = %b0
  store i32 %p1, ptr %p0, align 4
  ret void
}

define internal fastcc i32 @astra.fn.2(i1 %p0) {
b0:
  br i1 %p0, label %b1, label %b2

b1:                                               ; preds = %b0
  br label %b2

b2:                                               ; preds = %b1, %b0
  %v1 = phi i32 [ 1, %b0 ], [ 2, %b1 ]
  ret i32 %v1
}

define internal fastcc i32 @astra.fn.3() {
b0:
  %storage0 = alloca i32, align 4
  store i32 1, ptr %storage0, align 4
  br label %b3

b1:                                               ; preds = %b8
  ret i32 1

b2:                                               ; preds = %b8
  %memory1.null = icmp eq ptr %storage0, null
  br i1 %memory1.null, label %memory1.trap, label %memory1.nonnull

b3:                                               ; preds = %b0
  br label %b4

b4:                                               ; preds = %b3
  %v4 = icmp eq ptr %storage0, null
  br i1 %v4, label %b6, label %b5

b5:                                               ; preds = %b4
  %v5 = icmp eq ptr null, %storage0
  br label %b6

b6:                                               ; preds = %b5, %b4
  %v0 = phi i1 [ true, %b4 ], [ %v5, %b5 ]
  br i1 %v0, label %b8, label %b7

b7:                                               ; preds = %b6
  %v6 = icmp ne ptr %storage0, %storage0
  br label %b8

b8:                                               ; preds = %b7, %b6
  %v1 = phi i1 [ true, %b6 ], [ %v6, %b7 ]
  br i1 %v1, label %b1, label %b2

b9:                                               ; preds = %memory1.nonnull
  ret i32 2

b10:                                              ; preds = %memory1.nonnull
  store i32 3, ptr %storage0, align 4
  %memory4.null = icmp eq ptr %storage0, null
  br i1 %memory4.null, label %memory4.trap, label %memory4.nonnull

b11:                                              ; preds = %memory4.nonnull
  ret i32 3

b12:                                              ; preds = %memory4.nonnull
  call fastcc void @astra.fn.1(ptr %storage0, i32 42)
  br label %b15

b13:                                              ; preds = %b17
  ret i32 4

b14:                                              ; preds = %b17
  ret i32 0

b15:                                              ; preds = %b12
  %v12 = call fastcc i32 @astra.fn.0(ptr %storage0)
  %v13 = icmp ne i32 %v12, 42
  br i1 %v13, label %b17, label %b16

b16:                                              ; preds = %b15
  %v14 = call fastcc i32 @astra.fn.2(i1 true)
  %v15 = icmp ne i32 %v14, 2
  br label %b17

b17:                                              ; preds = %b16, %b15
  %v2 = phi i1 [ true, %b15 ], [ %v15, %b16 ]
  br i1 %v2, label %b13, label %b14

memory1.trap:                                     ; preds = %b2
  call void @llvm.trap()
  unreachable

memory1.nonnull:                                  ; preds = %b2
  store i32 2, ptr %storage0, align 4
  %v7 = load i32, ptr %storage0, align 4
  %v8 = icmp ne i32 %v7, 2
  br i1 %v8, label %b9, label %b10

memory4.trap:                                     ; preds = %b10
  call void @llvm.trap()
  unreachable

memory4.nonnull:                                  ; preds = %b10
  %v9 = load i32, ptr %storage0, align 4
  %v10 = icmp ne i32 %v9, 3
  br i1 %v10, label %b11, label %b12
}

; Function Attrs: cold noreturn nounwind memory(inaccessiblemem: write)
declare void @llvm.trap() #0

attributes #0 = { cold noreturn nounwind memory(inaccessiblemem: write) }
