; ModuleID = 'astra.scalar'
source_filename = "astra.scalar"

%astra.struct.1 = type { %astra.struct.0, %astra.struct.0 }
%astra.struct.0 = type { i32, double, <8 x i16> }

define internal fastcc void @astra.fn.0(ptr %p0, ptr %p1) {
b0:
  %validate0.null = icmp eq ptr %p0, null
  br i1 %validate0.null, label %validate0.trap, label %validate0.nonnull

validate0.trap:                                   ; preds = %b0
  call void @llvm.trap()
  unreachable

validate0.nonnull:                                ; preds = %b0
  %validate1.null = icmp eq ptr %p1, null
  br i1 %validate1.null, label %validate1.trap, label %validate1.nonnull

validate1.trap:                                   ; preds = %validate0.nonnull
  call void @llvm.trap()
  unreachable

validate1.nonnull:                                ; preds = %validate0.nonnull
  %memory2.base.base.null = icmp eq ptr %p1, null
  br i1 %memory2.base.base.null, label %memory2.base.base.trap, label %memory2.base.base.nonnull

memory2.base.base.trap:                           ; preds = %validate1.nonnull
  call void @llvm.trap()
  unreachable

memory2.base.base.nonnull:                        ; preds = %validate1.nonnull
  %memory2.base.field = getelementptr inbounds nuw %astra.struct.1, ptr %p1, i32 0, i32 0
  %memory2.field = getelementptr inbounds nuw %astra.struct.0, ptr %memory2.base.field, i32 0, i32 0
  %v2 = load i32, ptr %memory2.field, align 4
  %memory3.base.base.null = icmp eq ptr %p1, null
  br i1 %memory3.base.base.null, label %memory3.base.base.trap, label %memory3.base.base.nonnull

memory3.base.base.trap:                           ; preds = %memory2.base.base.nonnull
  call void @llvm.trap()
  unreachable

memory3.base.base.nonnull:                        ; preds = %memory2.base.base.nonnull
  %memory3.base.field = getelementptr inbounds nuw %astra.struct.1, ptr %p1, i32 0, i32 0
  %memory3.field = getelementptr inbounds nuw %astra.struct.0, ptr %memory3.base.field, i32 0, i32 1
  %v3 = load double, ptr %memory3.field, align 8
  %memory4.base.base.null = icmp eq ptr %p1, null
  br i1 %memory4.base.base.null, label %memory4.base.base.trap, label %memory4.base.base.nonnull

memory4.base.base.trap:                           ; preds = %memory3.base.base.nonnull
  call void @llvm.trap()
  unreachable

memory4.base.base.nonnull:                        ; preds = %memory3.base.base.nonnull
  %memory4.base.field = getelementptr inbounds nuw %astra.struct.1, ptr %p1, i32 0, i32 0
  %memory4.field = getelementptr inbounds nuw %astra.struct.0, ptr %memory4.base.field, i32 0, i32 2
  %v4 = load <8 x i16>, ptr %memory4.field, align 16
  %memory5.base.base.null = icmp eq ptr %p1, null
  br i1 %memory5.base.base.null, label %memory5.base.base.trap, label %memory5.base.base.nonnull

memory5.base.base.trap:                           ; preds = %memory4.base.base.nonnull
  call void @llvm.trap()
  unreachable

memory5.base.base.nonnull:                        ; preds = %memory4.base.base.nonnull
  %memory5.base.field = getelementptr inbounds nuw %astra.struct.1, ptr %p1, i32 0, i32 1
  %memory5.field = getelementptr inbounds nuw %astra.struct.0, ptr %memory5.base.field, i32 0, i32 0
  %v5 = load i32, ptr %memory5.field, align 4
  %memory6.base.base.null = icmp eq ptr %p1, null
  br i1 %memory6.base.base.null, label %memory6.base.base.trap, label %memory6.base.base.nonnull

memory6.base.base.trap:                           ; preds = %memory5.base.base.nonnull
  call void @llvm.trap()
  unreachable

memory6.base.base.nonnull:                        ; preds = %memory5.base.base.nonnull
  %memory6.base.field = getelementptr inbounds nuw %astra.struct.1, ptr %p1, i32 0, i32 1
  %memory6.field = getelementptr inbounds nuw %astra.struct.0, ptr %memory6.base.field, i32 0, i32 1
  %v6 = load double, ptr %memory6.field, align 8
  %memory7.base.base.null = icmp eq ptr %p1, null
  br i1 %memory7.base.base.null, label %memory7.base.base.trap, label %memory7.base.base.nonnull

memory7.base.base.trap:                           ; preds = %memory6.base.base.nonnull
  call void @llvm.trap()
  unreachable

memory7.base.base.nonnull:                        ; preds = %memory6.base.base.nonnull
  %memory7.base.field = getelementptr inbounds nuw %astra.struct.1, ptr %p1, i32 0, i32 1
  %memory7.field = getelementptr inbounds nuw %astra.struct.0, ptr %memory7.base.field, i32 0, i32 2
  %v7 = load <8 x i16>, ptr %memory7.field, align 16
  %memory8.base.base.null = icmp eq ptr %p0, null
  br i1 %memory8.base.base.null, label %memory8.base.base.trap, label %memory8.base.base.nonnull

memory8.base.base.trap:                           ; preds = %memory7.base.base.nonnull
  call void @llvm.trap()
  unreachable

memory8.base.base.nonnull:                        ; preds = %memory7.base.base.nonnull
  %memory8.base.field = getelementptr inbounds nuw %astra.struct.1, ptr %p0, i32 0, i32 0
  %memory8.field = getelementptr inbounds nuw %astra.struct.0, ptr %memory8.base.field, i32 0, i32 0
  store i32 %v2, ptr %memory8.field, align 4
  %memory9.base.base.null = icmp eq ptr %p0, null
  br i1 %memory9.base.base.null, label %memory9.base.base.trap, label %memory9.base.base.nonnull

memory9.base.base.trap:                           ; preds = %memory8.base.base.nonnull
  call void @llvm.trap()
  unreachable

memory9.base.base.nonnull:                        ; preds = %memory8.base.base.nonnull
  %memory9.base.field = getelementptr inbounds nuw %astra.struct.1, ptr %p0, i32 0, i32 0
  %memory9.field = getelementptr inbounds nuw %astra.struct.0, ptr %memory9.base.field, i32 0, i32 1
  store double %v3, ptr %memory9.field, align 8
  %memory10.base.base.null = icmp eq ptr %p0, null
  br i1 %memory10.base.base.null, label %memory10.base.base.trap, label %memory10.base.base.nonnull

memory10.base.base.trap:                          ; preds = %memory9.base.base.nonnull
  call void @llvm.trap()
  unreachable

memory10.base.base.nonnull:                       ; preds = %memory9.base.base.nonnull
  %memory10.base.field = getelementptr inbounds nuw %astra.struct.1, ptr %p0, i32 0, i32 0
  %memory10.field = getelementptr inbounds nuw %astra.struct.0, ptr %memory10.base.field, i32 0, i32 2
  store <8 x i16> %v4, ptr %memory10.field, align 16
  %memory11.base.base.null = icmp eq ptr %p0, null
  br i1 %memory11.base.base.null, label %memory11.base.base.trap, label %memory11.base.base.nonnull

memory11.base.base.trap:                          ; preds = %memory10.base.base.nonnull
  call void @llvm.trap()
  unreachable

memory11.base.base.nonnull:                       ; preds = %memory10.base.base.nonnull
  %memory11.base.field = getelementptr inbounds nuw %astra.struct.1, ptr %p0, i32 0, i32 1
  %memory11.field = getelementptr inbounds nuw %astra.struct.0, ptr %memory11.base.field, i32 0, i32 0
  store i32 %v5, ptr %memory11.field, align 4
  %memory12.base.base.null = icmp eq ptr %p0, null
  br i1 %memory12.base.base.null, label %memory12.base.base.trap, label %memory12.base.base.nonnull

memory12.base.base.trap:                          ; preds = %memory11.base.base.nonnull
  call void @llvm.trap()
  unreachable

memory12.base.base.nonnull:                       ; preds = %memory11.base.base.nonnull
  %memory12.base.field = getelementptr inbounds nuw %astra.struct.1, ptr %p0, i32 0, i32 1
  %memory12.field = getelementptr inbounds nuw %astra.struct.0, ptr %memory12.base.field, i32 0, i32 1
  store double %v6, ptr %memory12.field, align 8
  %memory13.base.base.null = icmp eq ptr %p0, null
  br i1 %memory13.base.base.null, label %memory13.base.base.trap, label %memory13.base.base.nonnull

memory13.base.base.trap:                          ; preds = %memory12.base.base.nonnull
  call void @llvm.trap()
  unreachable

memory13.base.base.nonnull:                       ; preds = %memory12.base.base.nonnull
  %memory13.base.field = getelementptr inbounds nuw %astra.struct.1, ptr %p0, i32 0, i32 1
  %memory13.field = getelementptr inbounds nuw %astra.struct.0, ptr %memory13.base.field, i32 0, i32 2
  store <8 x i16> %v7, ptr %memory13.field, align 16
  ret void
}

define internal fastcc i32 @astra.fn.1() {
b0:
  %storage0 = alloca %astra.struct.1, align 16
  %storage1 = alloca %astra.struct.1, align 16
  %memory0.base.field = getelementptr inbounds nuw %astra.struct.1, ptr %storage0, i32 0, i32 0
  %memory0.field = getelementptr inbounds nuw %astra.struct.0, ptr %memory0.base.field, i32 0, i32 0
  store i32 42, ptr %memory0.field, align 4
  %memory1.base.field = getelementptr inbounds nuw %astra.struct.1, ptr %storage0, i32 0, i32 0
  %memory1.field = getelementptr inbounds nuw %astra.struct.0, ptr %memory1.base.field, i32 0, i32 1
  store double 3.500000e+00, ptr %memory1.field, align 8
  %memory2.base.field = getelementptr inbounds nuw %astra.struct.1, ptr %storage0, i32 0, i32 0
  %memory2.field = getelementptr inbounds nuw %astra.struct.0, ptr %memory2.base.field, i32 0, i32 2
  store <8 x i16> splat (i16 7), ptr %memory2.field, align 16
  %memory3.base.field = getelementptr inbounds nuw %astra.struct.1, ptr %storage0, i32 0, i32 1
  %memory3.field = getelementptr inbounds nuw %astra.struct.0, ptr %memory3.base.field, i32 0, i32 0
  store i32 9, ptr %memory3.field, align 4
  %memory4.base.field = getelementptr inbounds nuw %astra.struct.1, ptr %storage0, i32 0, i32 1
  %memory4.field = getelementptr inbounds nuw %astra.struct.0, ptr %memory4.base.field, i32 0, i32 1
  store double 1.500000e+00, ptr %memory4.field, align 8
  %memory5.base.field = getelementptr inbounds nuw %astra.struct.1, ptr %storage0, i32 0, i32 1
  %memory5.field = getelementptr inbounds nuw %astra.struct.0, ptr %memory5.base.field, i32 0, i32 2
  store <8 x i16> splat (i16 2), ptr %memory5.field, align 16
  %memory6.base.field = getelementptr inbounds nuw %astra.struct.1, ptr %storage0, i32 0, i32 0
  %memory6.field = getelementptr inbounds nuw %astra.struct.0, ptr %memory6.base.field, i32 0, i32 0
  %v5 = load i32, ptr %memory6.field, align 4
  %memory7.base.field = getelementptr inbounds nuw %astra.struct.1, ptr %storage0, i32 0, i32 0
  %memory7.field = getelementptr inbounds nuw %astra.struct.0, ptr %memory7.base.field, i32 0, i32 1
  %v6 = load double, ptr %memory7.field, align 8
  %memory8.base.field = getelementptr inbounds nuw %astra.struct.1, ptr %storage0, i32 0, i32 0
  %memory8.field = getelementptr inbounds nuw %astra.struct.0, ptr %memory8.base.field, i32 0, i32 2
  %v7 = load <8 x i16>, ptr %memory8.field, align 16
  %memory9.base.field = getelementptr inbounds nuw %astra.struct.1, ptr %storage0, i32 0, i32 1
  %memory9.field = getelementptr inbounds nuw %astra.struct.0, ptr %memory9.base.field, i32 0, i32 0
  %v8 = load i32, ptr %memory9.field, align 4
  %memory10.base.field = getelementptr inbounds nuw %astra.struct.1, ptr %storage0, i32 0, i32 1
  %memory10.field = getelementptr inbounds nuw %astra.struct.0, ptr %memory10.base.field, i32 0, i32 1
  %v9 = load double, ptr %memory10.field, align 8
  %memory11.base.field = getelementptr inbounds nuw %astra.struct.1, ptr %storage0, i32 0, i32 1
  %memory11.field = getelementptr inbounds nuw %astra.struct.0, ptr %memory11.base.field, i32 0, i32 2
  %v10 = load <8 x i16>, ptr %memory11.field, align 16
  %memory12.base.field = getelementptr inbounds nuw %astra.struct.1, ptr %storage1, i32 0, i32 0
  %memory12.field = getelementptr inbounds nuw %astra.struct.0, ptr %memory12.base.field, i32 0, i32 0
  store i32 %v5, ptr %memory12.field, align 4
  %memory13.base.field = getelementptr inbounds nuw %astra.struct.1, ptr %storage1, i32 0, i32 0
  %memory13.field = getelementptr inbounds nuw %astra.struct.0, ptr %memory13.base.field, i32 0, i32 1
  store double %v6, ptr %memory13.field, align 8
  %memory14.base.field = getelementptr inbounds nuw %astra.struct.1, ptr %storage1, i32 0, i32 0
  %memory14.field = getelementptr inbounds nuw %astra.struct.0, ptr %memory14.base.field, i32 0, i32 2
  store <8 x i16> %v7, ptr %memory14.field, align 16
  %memory15.base.field = getelementptr inbounds nuw %astra.struct.1, ptr %storage1, i32 0, i32 1
  %memory15.field = getelementptr inbounds nuw %astra.struct.0, ptr %memory15.base.field, i32 0, i32 0
  store i32 %v8, ptr %memory15.field, align 4
  %memory16.base.field = getelementptr inbounds nuw %astra.struct.1, ptr %storage1, i32 0, i32 1
  %memory16.field = getelementptr inbounds nuw %astra.struct.0, ptr %memory16.base.field, i32 0, i32 1
  store double %v9, ptr %memory16.field, align 8
  %memory17.base.field = getelementptr inbounds nuw %astra.struct.1, ptr %storage1, i32 0, i32 1
  %memory17.field = getelementptr inbounds nuw %astra.struct.0, ptr %memory17.base.field, i32 0, i32 2
  store <8 x i16> %v10, ptr %memory17.field, align 16
  call fastcc void @astra.fn.0(ptr %storage1, ptr %storage0)
  %validate18.null = icmp eq ptr %storage1, null
  br i1 %validate18.null, label %validate18.trap, label %validate18.nonnull

b1:                                               ; preds = %b11
  ret i32 1

b2:                                               ; preds = %b11
  ret i32 0

b3:                                               ; preds = %memory39.base.base.nonnull
  br label %b4

b4:                                               ; preds = %b3
  br label %b5

b5:                                               ; preds = %b4
  %memory40.base.field = getelementptr inbounds nuw %astra.struct.1, ptr %storage0, i32 0, i32 0
  %memory40.field = getelementptr inbounds nuw %astra.struct.0, ptr %memory40.base.field, i32 0, i32 0
  %v22 = load i32, ptr %memory40.field, align 4
  %v23 = icmp ne i32 %v22, 42
  br i1 %v23, label %b7, label %b6

b6:                                               ; preds = %b5
  %memory42.base.field = getelementptr inbounds nuw %astra.struct.1, ptr %storage1, i32 0, i32 0
  %memory42.field = getelementptr inbounds nuw %astra.struct.0, ptr %memory42.base.field, i32 0, i32 0
  %v24 = load i32, ptr %memory42.field, align 4
  %v25 = icmp ne i32 %v24, 9
  br label %b7

b7:                                               ; preds = %b6, %b5
  %v0 = phi i1 [ true, %b5 ], [ %v25, %b6 ]
  br i1 %v0, label %b9, label %b8

b8:                                               ; preds = %b7
  %v26 = icmp ne i32 %v13, 42
  br label %b9

b9:                                               ; preds = %b8, %b7
  %v1 = phi i1 [ true, %b7 ], [ %v26, %b8 ]
  br i1 %v1, label %b11, label %b10

b10:                                              ; preds = %b9
  %memory41.base.field = getelementptr inbounds nuw %astra.struct.1, ptr %storage1, i32 0, i32 0
  %memory41.field = getelementptr inbounds nuw %astra.struct.0, ptr %memory41.base.field, i32 0, i32 2
  %v27 = load <8 x i16>, ptr %memory41.field, align 16
  %v28 = extractelement <8 x i16> %v27, i32 7
  %v29 = icmp ne i16 %v28, 2
  br label %b11

b11:                                              ; preds = %b10, %b9
  %v2 = phi i1 [ true, %b9 ], [ %v29, %b10 ]
  br i1 %v2, label %b1, label %b2

validate18.trap:                                  ; preds = %b0
  call void @llvm.trap()
  unreachable

validate18.nonnull:                               ; preds = %b0
  %memory19.base.base.null = icmp eq ptr %storage1, null
  br i1 %memory19.base.base.null, label %memory19.base.base.trap, label %memory19.base.base.nonnull

memory19.base.base.trap:                          ; preds = %validate18.nonnull
  call void @llvm.trap()
  unreachable

memory19.base.base.nonnull:                       ; preds = %validate18.nonnull
  %memory19.base.field = getelementptr inbounds nuw %astra.struct.1, ptr %storage1, i32 0, i32 0
  %memory19.field = getelementptr inbounds nuw %astra.struct.0, ptr %memory19.base.field, i32 0, i32 0
  %v13 = load i32, ptr %memory19.field, align 4
  %memory20.base.base.null = icmp eq ptr %storage1, null
  br i1 %memory20.base.base.null, label %memory20.base.base.trap, label %memory20.base.base.nonnull

memory20.base.base.trap:                          ; preds = %memory19.base.base.nonnull
  call void @llvm.trap()
  unreachable

memory20.base.base.nonnull:                       ; preds = %memory19.base.base.nonnull
  %memory20.base.field = getelementptr inbounds nuw %astra.struct.1, ptr %storage1, i32 0, i32 0
  %memory20.field = getelementptr inbounds nuw %astra.struct.0, ptr %memory20.base.field, i32 0, i32 1
  %v14 = load double, ptr %memory20.field, align 8
  %memory21.base.base.null = icmp eq ptr %storage1, null
  br i1 %memory21.base.base.null, label %memory21.base.base.trap, label %memory21.base.base.nonnull

memory21.base.base.trap:                          ; preds = %memory20.base.base.nonnull
  call void @llvm.trap()
  unreachable

memory21.base.base.nonnull:                       ; preds = %memory20.base.base.nonnull
  %memory21.base.field = getelementptr inbounds nuw %astra.struct.1, ptr %storage1, i32 0, i32 0
  %memory21.field = getelementptr inbounds nuw %astra.struct.0, ptr %memory21.base.field, i32 0, i32 2
  %v15 = load <8 x i16>, ptr %memory21.field, align 16
  %memory22.base.base.null = icmp eq ptr %storage1, null
  br i1 %memory22.base.base.null, label %memory22.base.base.trap, label %memory22.base.base.nonnull

memory22.base.base.trap:                          ; preds = %memory21.base.base.nonnull
  call void @llvm.trap()
  unreachable

memory22.base.base.nonnull:                       ; preds = %memory21.base.base.nonnull
  %memory22.base.field = getelementptr inbounds nuw %astra.struct.1, ptr %storage1, i32 0, i32 1
  %memory22.field = getelementptr inbounds nuw %astra.struct.0, ptr %memory22.base.field, i32 0, i32 0
  %v16 = load i32, ptr %memory22.field, align 4
  %memory23.base.base.null = icmp eq ptr %storage1, null
  br i1 %memory23.base.base.null, label %memory23.base.base.trap, label %memory23.base.base.nonnull

memory23.base.base.trap:                          ; preds = %memory22.base.base.nonnull
  call void @llvm.trap()
  unreachable

memory23.base.base.nonnull:                       ; preds = %memory22.base.base.nonnull
  %memory23.base.field = getelementptr inbounds nuw %astra.struct.1, ptr %storage1, i32 0, i32 1
  %memory23.field = getelementptr inbounds nuw %astra.struct.0, ptr %memory23.base.field, i32 0, i32 1
  %v17 = load double, ptr %memory23.field, align 8
  %memory24.base.base.null = icmp eq ptr %storage1, null
  br i1 %memory24.base.base.null, label %memory24.base.base.trap, label %memory24.base.base.nonnull

memory24.base.base.trap:                          ; preds = %memory23.base.base.nonnull
  call void @llvm.trap()
  unreachable

memory24.base.base.nonnull:                       ; preds = %memory23.base.base.nonnull
  %memory24.base.field = getelementptr inbounds nuw %astra.struct.1, ptr %storage1, i32 0, i32 1
  %memory24.field = getelementptr inbounds nuw %astra.struct.0, ptr %memory24.base.field, i32 0, i32 2
  %v18 = load <8 x i16>, ptr %memory24.field, align 16
  %validate25.null = icmp eq ptr %storage0, null
  br i1 %validate25.null, label %validate25.trap, label %validate25.nonnull

validate25.trap:                                  ; preds = %memory24.base.base.nonnull
  call void @llvm.trap()
  unreachable

validate25.nonnull:                               ; preds = %memory24.base.base.nonnull
  %memory26.base.base.null = icmp eq ptr %storage0, null
  br i1 %memory26.base.base.null, label %memory26.base.base.trap, label %memory26.base.base.nonnull

memory26.base.base.trap:                          ; preds = %validate25.nonnull
  call void @llvm.trap()
  unreachable

memory26.base.base.nonnull:                       ; preds = %validate25.nonnull
  %memory26.base.field = getelementptr inbounds nuw %astra.struct.1, ptr %storage0, i32 0, i32 0
  %memory26.field = getelementptr inbounds nuw %astra.struct.0, ptr %memory26.base.field, i32 0, i32 0
  store i32 %v13, ptr %memory26.field, align 4
  %memory27.base.base.null = icmp eq ptr %storage0, null
  br i1 %memory27.base.base.null, label %memory27.base.base.trap, label %memory27.base.base.nonnull

memory27.base.base.trap:                          ; preds = %memory26.base.base.nonnull
  call void @llvm.trap()
  unreachable

memory27.base.base.nonnull:                       ; preds = %memory26.base.base.nonnull
  %memory27.base.field = getelementptr inbounds nuw %astra.struct.1, ptr %storage0, i32 0, i32 0
  %memory27.field = getelementptr inbounds nuw %astra.struct.0, ptr %memory27.base.field, i32 0, i32 1
  store double %v14, ptr %memory27.field, align 8
  %memory28.base.base.null = icmp eq ptr %storage0, null
  br i1 %memory28.base.base.null, label %memory28.base.base.trap, label %memory28.base.base.nonnull

memory28.base.base.trap:                          ; preds = %memory27.base.base.nonnull
  call void @llvm.trap()
  unreachable

memory28.base.base.nonnull:                       ; preds = %memory27.base.base.nonnull
  %memory28.base.field = getelementptr inbounds nuw %astra.struct.1, ptr %storage0, i32 0, i32 0
  %memory28.field = getelementptr inbounds nuw %astra.struct.0, ptr %memory28.base.field, i32 0, i32 2
  store <8 x i16> %v15, ptr %memory28.field, align 16
  %memory29.base.base.null = icmp eq ptr %storage0, null
  br i1 %memory29.base.base.null, label %memory29.base.base.trap, label %memory29.base.base.nonnull

memory29.base.base.trap:                          ; preds = %memory28.base.base.nonnull
  call void @llvm.trap()
  unreachable

memory29.base.base.nonnull:                       ; preds = %memory28.base.base.nonnull
  %memory29.base.field = getelementptr inbounds nuw %astra.struct.1, ptr %storage0, i32 0, i32 1
  %memory29.field = getelementptr inbounds nuw %astra.struct.0, ptr %memory29.base.field, i32 0, i32 0
  store i32 %v16, ptr %memory29.field, align 4
  %memory30.base.base.null = icmp eq ptr %storage0, null
  br i1 %memory30.base.base.null, label %memory30.base.base.trap, label %memory30.base.base.nonnull

memory30.base.base.trap:                          ; preds = %memory29.base.base.nonnull
  call void @llvm.trap()
  unreachable

memory30.base.base.nonnull:                       ; preds = %memory29.base.base.nonnull
  %memory30.base.field = getelementptr inbounds nuw %astra.struct.1, ptr %storage0, i32 0, i32 1
  %memory30.field = getelementptr inbounds nuw %astra.struct.0, ptr %memory30.base.field, i32 0, i32 1
  store double %v17, ptr %memory30.field, align 8
  %memory31.base.base.null = icmp eq ptr %storage0, null
  br i1 %memory31.base.base.null, label %memory31.base.base.trap, label %memory31.base.base.nonnull

memory31.base.base.trap:                          ; preds = %memory30.base.base.nonnull
  call void @llvm.trap()
  unreachable

memory31.base.base.nonnull:                       ; preds = %memory30.base.base.nonnull
  %memory31.base.field = getelementptr inbounds nuw %astra.struct.1, ptr %storage0, i32 0, i32 1
  %memory31.field = getelementptr inbounds nuw %astra.struct.0, ptr %memory31.base.field, i32 0, i32 2
  store <8 x i16> %v18, ptr %memory31.field, align 16
  %validate32.base.null = icmp eq ptr %storage0, null
  br i1 %validate32.base.null, label %validate32.base.trap, label %validate32.base.nonnull

validate32.base.trap:                             ; preds = %memory31.base.base.nonnull
  call void @llvm.trap()
  unreachable

validate32.base.nonnull:                          ; preds = %memory31.base.base.nonnull
  %validate32.field = getelementptr inbounds nuw %astra.struct.1, ptr %storage0, i32 0, i32 1
  %memory33.base.base.null = icmp eq ptr %storage0, null
  br i1 %memory33.base.base.null, label %memory33.base.base.trap, label %memory33.base.base.nonnull

memory33.base.base.trap:                          ; preds = %validate32.base.nonnull
  call void @llvm.trap()
  unreachable

memory33.base.base.nonnull:                       ; preds = %validate32.base.nonnull
  %memory33.base.field = getelementptr inbounds nuw %astra.struct.1, ptr %storage0, i32 0, i32 1
  %memory33.field = getelementptr inbounds nuw %astra.struct.0, ptr %memory33.base.field, i32 0, i32 0
  %v19 = load i32, ptr %memory33.field, align 4
  %memory34.base.base.null = icmp eq ptr %storage0, null
  br i1 %memory34.base.base.null, label %memory34.base.base.trap, label %memory34.base.base.nonnull

memory34.base.base.trap:                          ; preds = %memory33.base.base.nonnull
  call void @llvm.trap()
  unreachable

memory34.base.base.nonnull:                       ; preds = %memory33.base.base.nonnull
  %memory34.base.field = getelementptr inbounds nuw %astra.struct.1, ptr %storage0, i32 0, i32 1
  %memory34.field = getelementptr inbounds nuw %astra.struct.0, ptr %memory34.base.field, i32 0, i32 1
  %v20 = load double, ptr %memory34.field, align 8
  %memory35.base.base.null = icmp eq ptr %storage0, null
  br i1 %memory35.base.base.null, label %memory35.base.base.trap, label %memory35.base.base.nonnull

memory35.base.base.trap:                          ; preds = %memory34.base.base.nonnull
  call void @llvm.trap()
  unreachable

memory35.base.base.nonnull:                       ; preds = %memory34.base.base.nonnull
  %memory35.base.field = getelementptr inbounds nuw %astra.struct.1, ptr %storage0, i32 0, i32 1
  %memory35.field = getelementptr inbounds nuw %astra.struct.0, ptr %memory35.base.field, i32 0, i32 2
  %v21 = load <8 x i16>, ptr %memory35.field, align 16
  %validate36.base.null = icmp eq ptr %storage1, null
  br i1 %validate36.base.null, label %validate36.base.trap, label %validate36.base.nonnull

validate36.base.trap:                             ; preds = %memory35.base.base.nonnull
  call void @llvm.trap()
  unreachable

validate36.base.nonnull:                          ; preds = %memory35.base.base.nonnull
  %validate36.field = getelementptr inbounds nuw %astra.struct.1, ptr %storage1, i32 0, i32 0
  %memory37.base.base.null = icmp eq ptr %storage1, null
  br i1 %memory37.base.base.null, label %memory37.base.base.trap, label %memory37.base.base.nonnull

memory37.base.base.trap:                          ; preds = %validate36.base.nonnull
  call void @llvm.trap()
  unreachable

memory37.base.base.nonnull:                       ; preds = %validate36.base.nonnull
  %memory37.base.field = getelementptr inbounds nuw %astra.struct.1, ptr %storage1, i32 0, i32 0
  %memory37.field = getelementptr inbounds nuw %astra.struct.0, ptr %memory37.base.field, i32 0, i32 0
  store i32 %v19, ptr %memory37.field, align 4
  %memory38.base.base.null = icmp eq ptr %storage1, null
  br i1 %memory38.base.base.null, label %memory38.base.base.trap, label %memory38.base.base.nonnull

memory38.base.base.trap:                          ; preds = %memory37.base.base.nonnull
  call void @llvm.trap()
  unreachable

memory38.base.base.nonnull:                       ; preds = %memory37.base.base.nonnull
  %memory38.base.field = getelementptr inbounds nuw %astra.struct.1, ptr %storage1, i32 0, i32 0
  %memory38.field = getelementptr inbounds nuw %astra.struct.0, ptr %memory38.base.field, i32 0, i32 1
  store double %v20, ptr %memory38.field, align 8
  %memory39.base.base.null = icmp eq ptr %storage1, null
  br i1 %memory39.base.base.null, label %memory39.base.base.trap, label %memory39.base.base.nonnull

memory39.base.base.trap:                          ; preds = %memory38.base.base.nonnull
  call void @llvm.trap()
  unreachable

memory39.base.base.nonnull:                       ; preds = %memory38.base.base.nonnull
  %memory39.base.field = getelementptr inbounds nuw %astra.struct.1, ptr %storage1, i32 0, i32 0
  %memory39.field = getelementptr inbounds nuw %astra.struct.0, ptr %memory39.base.field, i32 0, i32 2
  store <8 x i16> %v21, ptr %memory39.field, align 16
  br label %b3
}

; Function Attrs: cold noreturn nounwind memory(inaccessiblemem: write)
declare void @llvm.trap() #0

attributes #0 = { cold noreturn nounwind memory(inaccessiblemem: write) }
