; ModuleID = 'astra.scalar'
source_filename = "astra.scalar"

%astra.struct.0 = type { i32 }

define internal fastcc i32 @astra.fn.0() {
b0:
  %storage0 = alloca %astra.struct.0, align 8
  %memory0.field = getelementptr inbounds nuw %astra.struct.0, ptr %storage0, i32 0, i32 0
  store i32 42, ptr %memory0.field, align 4
  %memory1.field = getelementptr inbounds nuw %astra.struct.0, ptr %storage0, i32 0, i32 0
  store i32 42, ptr %memory1.field, align 4
  %validate2.null = icmp eq ptr %storage0, null
  br i1 %validate2.null, label %validate2.trap, label %validate2.nonnull

b1:                                               ; preds = %b26
  ret i32 1

b2:                                               ; preds = %b26
  ret i32 0

b3:                                               ; preds = %memory5.base.nonnull
  br label %b4

b4:                                               ; preds = %b3
  br label %b5

b5:                                               ; preds = %b4
  br label %b6

b6:                                               ; preds = %b5
  br label %b7

b7:                                               ; preds = %b6
  br label %b8

b8:                                               ; preds = %b7
  br label %b9

b9:                                               ; preds = %b8
  br label %b10

b10:                                              ; preds = %b9
  br i1 false, label %b12, label %b11

b11:                                              ; preds = %b10
  br label %b12

b12:                                              ; preds = %b11, %b10
  %v0 = phi i1 [ true, %b10 ], [ false, %b11 ]
  br i1 %v0, label %b14, label %b13

b13:                                              ; preds = %b12
  %v13 = icmp ne i32 %v10, 42
  br label %b14

b14:                                              ; preds = %b13, %b12
  %v1 = phi i1 [ true, %b12 ], [ %v13, %b13 ]
  br i1 %v1, label %b16, label %b15

b15:                                              ; preds = %b14
  br label %b16

b16:                                              ; preds = %b15, %b14
  %v2 = phi i1 [ true, %b14 ], [ false, %b15 ]
  br i1 %v2, label %b18, label %b17

b17:                                              ; preds = %b16
  br label %b18

b18:                                              ; preds = %b17, %b16
  %v3 = phi i1 [ true, %b16 ], [ false, %b17 ]
  br i1 %v3, label %b20, label %b19

b19:                                              ; preds = %b18
  br label %b20

b20:                                              ; preds = %b19, %b18
  %v4 = phi i1 [ true, %b18 ], [ false, %b19 ]
  br i1 %v4, label %b22, label %b21

b21:                                              ; preds = %b20
  br label %b22

b22:                                              ; preds = %b21, %b20
  %v5 = phi i1 [ true, %b20 ], [ false, %b21 ]
  br i1 %v5, label %b24, label %b23

b23:                                              ; preds = %b22
  br label %b24

b24:                                              ; preds = %b23, %b22
  %v6 = phi i1 [ true, %b22 ], [ false, %b23 ]
  br i1 %v6, label %b26, label %b25

b25:                                              ; preds = %b24
  %v20 = call fastcc i32 @astra.fn.1(i32 42)
  %v21 = icmp ne i32 %v20, 42
  br label %b26

b26:                                              ; preds = %b25, %b24
  %v7 = phi i1 [ true, %b24 ], [ %v21, %b25 ]
  br i1 %v7, label %b1, label %b2

validate2.trap:                                   ; preds = %b0
  call void @llvm.trap()
  unreachable

validate2.nonnull:                                ; preds = %b0
  %memory3.base.null = icmp eq ptr %storage0, null
  br i1 %memory3.base.null, label %memory3.base.trap, label %memory3.base.nonnull

memory3.base.trap:                                ; preds = %validate2.nonnull
  call void @llvm.trap()
  unreachable

memory3.base.nonnull:                             ; preds = %validate2.nonnull
  %memory3.field = getelementptr inbounds nuw %astra.struct.0, ptr %storage0, i32 0, i32 0
  store i32 42, ptr %memory3.field, align 4
  %validate4.null = icmp eq ptr %storage0, null
  br i1 %validate4.null, label %validate4.trap, label %validate4.nonnull

validate4.trap:                                   ; preds = %memory3.base.nonnull
  call void @llvm.trap()
  unreachable

validate4.nonnull:                                ; preds = %memory3.base.nonnull
  %memory5.base.null = icmp eq ptr %storage0, null
  br i1 %memory5.base.null, label %memory5.base.trap, label %memory5.base.nonnull

memory5.base.trap:                                ; preds = %validate4.nonnull
  call void @llvm.trap()
  unreachable

memory5.base.nonnull:                             ; preds = %validate4.nonnull
  %memory5.field = getelementptr inbounds nuw %astra.struct.0, ptr %storage0, i32 0, i32 0
  %v10 = load i32, ptr %memory5.field, align 4
  br label %b3
}

define internal fastcc i32 @astra.fn.1(i32 %p0) {
b0:
  ret i32 %p0
}

; Function Attrs: cold noreturn nounwind memory(inaccessiblemem: write)
declare void @llvm.trap() #0

attributes #0 = { cold noreturn nounwind memory(inaccessiblemem: write) }
