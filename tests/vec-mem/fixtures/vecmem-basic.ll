; ModuleID = 'astra.scalar'
source_filename = "astra.scalar"

define internal fastcc void @astra.fn.0(ptr %p0) {
b0:
  %memory0.null = icmp eq ptr %p0, null
  br i1 %memory0.null, label %memory0.trap, label %memory0.nonnull

memory0.trap:                                     ; preds = %b0
  call void @llvm.trap()
  unreachable

memory0.nonnull:                                  ; preds = %b0
  store <8 x i16> zeroinitializer, ptr %p0, align 16
  ret void
}

define internal fastcc void @astra.fn.1(ptr %p0) {
b0:
  call fastcc void @astra.fn.0(ptr %p0)
  ret void
}

define internal fastcc i32 @astra.fn.2() {
b0:
  %storage0 = alloca <8 x i16>, align 16
  %storage1 = alloca <4 x i32>, align 16
  store <8 x i16> <i16 1, i16 2, i16 3, i16 4, i16 5, i16 6, i16 7, i16 8>, ptr %storage0, align 16
  %memory1.null = icmp eq ptr %storage0, null
  br i1 %memory1.null, label %memory1.trap, label %memory1.nonnull

b1:                                               ; preds = %memory1.nonnull
  ret i32 1

b2:                                               ; preds = %memory1.nonnull
  %memory3.null = icmp eq ptr %storage0, null
  br i1 %memory3.null, label %memory3.trap, label %memory3.nonnull

b3:                                               ; preds = %memory3.nonnull
  ret i32 2

b4:                                               ; preds = %memory3.nonnull
  call fastcc void @astra.fn.1(ptr %storage0)
  %v14 = load <8 x i16>, ptr %storage0, align 16
  %v16 = icmp eq <8 x i16> %v14, zeroinitializer
  %v17.lane0 = extractelement <8 x i1> %v16, i32 0
  %v17.lane1 = extractelement <8 x i1> %v16, i32 1
  %v17.reduce1 = and i1 %v17.lane0, %v17.lane1
  %v17.lane2 = extractelement <8 x i1> %v16, i32 2
  %v17.reduce2 = and i1 %v17.reduce1, %v17.lane2
  %v17.lane3 = extractelement <8 x i1> %v16, i32 3
  %v17.reduce3 = and i1 %v17.reduce2, %v17.lane3
  %v17.lane4 = extractelement <8 x i1> %v16, i32 4
  %v17.reduce4 = and i1 %v17.reduce3, %v17.lane4
  %v17.lane5 = extractelement <8 x i1> %v16, i32 5
  %v17.reduce5 = and i1 %v17.reduce4, %v17.lane5
  %v17.lane6 = extractelement <8 x i1> %v16, i32 6
  %v17.reduce6 = and i1 %v17.reduce5, %v17.lane6
  %v17.lane7 = extractelement <8 x i1> %v16, i32 7
  %v17 = and i1 %v17.reduce6, %v17.lane7
  %v18 = xor i1 %v17, true
  br i1 %v18, label %b5, label %b6

b5:                                               ; preds = %b4
  ret i32 3

b6:                                               ; preds = %b4
  store <4 x i32> <i32 1, i32 2, i32 3, i32 4>, ptr %storage1, align 16
  %memory7.null = icmp eq ptr %storage1, null
  br i1 %memory7.null, label %memory7.trap, label %memory7.nonnull

b7:                                               ; preds = %b11
  ret i32 4

b8:                                               ; preds = %b11
  ret i32 0

b9:                                               ; preds = %memory7.nonnull
  %v22 = icmp ne ptr %storage1, %storage1
  br i1 %v22, label %b11, label %b10

b10:                                              ; preds = %b9
  %v23 = load <4 x i32>, ptr %storage1, align 16
  %v25 = icmp eq <4 x i32> %v23, splat (i32 7)
  %v26.lane0 = extractelement <4 x i1> %v25, i32 0
  %v26.lane1 = extractelement <4 x i1> %v25, i32 1
  %v26.reduce1 = and i1 %v26.lane0, %v26.lane1
  %v26.lane2 = extractelement <4 x i1> %v25, i32 2
  %v26.reduce2 = and i1 %v26.reduce1, %v26.lane2
  %v26.lane3 = extractelement <4 x i1> %v25, i32 3
  %v26 = and i1 %v26.reduce2, %v26.lane3
  %v27 = xor i1 %v26, true
  br label %b11

b11:                                              ; preds = %b10, %b9
  %v0 = phi i1 [ true, %b9 ], [ %v27, %b10 ]
  br i1 %v0, label %b7, label %b8

memory1.trap:                                     ; preds = %b0
  call void @llvm.trap()
  unreachable

memory1.nonnull:                                  ; preds = %b0
  store <8 x i16> splat (i16 42), ptr %storage0, align 16
  %v4 = load <8 x i16>, ptr %storage0, align 16
  %v6 = icmp eq <8 x i16> %v4, splat (i16 42)
  %v7.lane0 = extractelement <8 x i1> %v6, i32 0
  %v7.lane1 = extractelement <8 x i1> %v6, i32 1
  %v7.reduce1 = and i1 %v7.lane0, %v7.lane1
  %v7.lane2 = extractelement <8 x i1> %v6, i32 2
  %v7.reduce2 = and i1 %v7.reduce1, %v7.lane2
  %v7.lane3 = extractelement <8 x i1> %v6, i32 3
  %v7.reduce3 = and i1 %v7.reduce2, %v7.lane3
  %v7.lane4 = extractelement <8 x i1> %v6, i32 4
  %v7.reduce4 = and i1 %v7.reduce3, %v7.lane4
  %v7.lane5 = extractelement <8 x i1> %v6, i32 5
  %v7.reduce5 = and i1 %v7.reduce4, %v7.lane5
  %v7.lane6 = extractelement <8 x i1> %v6, i32 6
  %v7.reduce6 = and i1 %v7.reduce5, %v7.lane6
  %v7.lane7 = extractelement <8 x i1> %v6, i32 7
  %v7 = and i1 %v7.reduce6, %v7.lane7
  %v8 = xor i1 %v7, true
  br i1 %v8, label %b1, label %b2

memory3.trap:                                     ; preds = %b2
  call void @llvm.trap()
  unreachable

memory3.nonnull:                                  ; preds = %b2
  %v9 = load <8 x i16>, ptr %storage0, align 16
  %v10 = load <8 x i16>, ptr %storage0, align 16
  %v11 = icmp eq <8 x i16> %v9, %v10
  %v12.lane0 = extractelement <8 x i1> %v11, i32 0
  %v12.lane1 = extractelement <8 x i1> %v11, i32 1
  %v12.reduce1 = and i1 %v12.lane0, %v12.lane1
  %v12.lane2 = extractelement <8 x i1> %v11, i32 2
  %v12.reduce2 = and i1 %v12.reduce1, %v12.lane2
  %v12.lane3 = extractelement <8 x i1> %v11, i32 3
  %v12.reduce3 = and i1 %v12.reduce2, %v12.lane3
  %v12.lane4 = extractelement <8 x i1> %v11, i32 4
  %v12.reduce4 = and i1 %v12.reduce3, %v12.lane4
  %v12.lane5 = extractelement <8 x i1> %v11, i32 5
  %v12.reduce5 = and i1 %v12.reduce4, %v12.lane5
  %v12.lane6 = extractelement <8 x i1> %v11, i32 6
  %v12.reduce6 = and i1 %v12.reduce5, %v12.lane6
  %v12.lane7 = extractelement <8 x i1> %v11, i32 7
  %v12 = and i1 %v12.reduce6, %v12.lane7
  %v13 = xor i1 %v12, true
  br i1 %v13, label %b3, label %b4

memory7.trap:                                     ; preds = %b6
  call void @llvm.trap()
  unreachable

memory7.nonnull:                                  ; preds = %b6
  store <4 x i32> splat (i32 7), ptr %storage1, align 16
  br label %b9
}

; Function Attrs: cold noreturn nounwind memory(inaccessiblemem: write)
declare void @llvm.trap() #0

attributes #0 = { cold noreturn nounwind memory(inaccessiblemem: write) }
