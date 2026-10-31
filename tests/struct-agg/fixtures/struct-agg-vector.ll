; ModuleID = 'astra.scalar'
source_filename = "astra.scalar"

%astra.struct.1 = type { %astra.struct.0 }
%astra.struct.0 = type { <4 x float>, <8 x i16>, <4 x i1> }

define internal fastcc void @astra.fn.0(ptr %p0, <8 x i16> %p1) {
b0:
  %memory0.base.base.null = icmp eq ptr %p0, null
  br i1 %memory0.base.base.null, label %memory0.base.base.trap, label %memory0.base.base.nonnull

memory0.base.base.trap:                           ; preds = %b0
  call void @llvm.trap()
  unreachable

memory0.base.base.nonnull:                        ; preds = %b0
  %memory0.base.field = getelementptr inbounds nuw %astra.struct.1, ptr %p0, i32 0, i32 0
  %memory0.field = getelementptr inbounds nuw %astra.struct.0, ptr %memory0.base.field, i32 0, i32 1
  store <8 x i16> %p1, ptr %memory0.field, align 16
  %memory1.base.base.null = icmp eq ptr %p0, null
  br i1 %memory1.base.base.null, label %memory1.base.base.trap, label %memory1.base.base.nonnull

memory1.base.base.trap:                           ; preds = %memory0.base.base.nonnull
  call void @llvm.trap()
  unreachable

memory1.base.base.nonnull:                        ; preds = %memory0.base.base.nonnull
  %memory1.base.field = getelementptr inbounds nuw %astra.struct.1, ptr %p0, i32 0, i32 0
  %memory1.field = getelementptr inbounds nuw %astra.struct.0, ptr %memory1.base.field, i32 0, i32 0
  %v2 = load <4 x float>, ptr %memory1.field, align 16
  %v3 = insertelement <4 x float> %v2, float 4.500000e+00, i32 2
  %memory2.base.base.null = icmp eq ptr %p0, null
  br i1 %memory2.base.base.null, label %memory2.base.base.trap, label %memory2.base.base.nonnull

memory2.base.base.trap:                           ; preds = %memory1.base.base.nonnull
  call void @llvm.trap()
  unreachable

memory2.base.base.nonnull:                        ; preds = %memory1.base.base.nonnull
  %memory2.base.field = getelementptr inbounds nuw %astra.struct.1, ptr %p0, i32 0, i32 0
  %memory2.field = getelementptr inbounds nuw %astra.struct.0, ptr %memory2.base.field, i32 0, i32 0
  store <4 x float> %v3, ptr %memory2.field, align 16
  ret void
}

define internal fastcc i32 @astra.fn.1() {
b0:
  %storage0 = alloca %astra.struct.1, align 16
  %memory0.base.field = getelementptr inbounds nuw %astra.struct.1, ptr %storage0, i32 0, i32 0
  %memory0.field = getelementptr inbounds nuw %astra.struct.0, ptr %memory0.base.field, i32 0, i32 0
  store <4 x float> <float 5.000000e-01, float 1.500000e+00, float 2.500000e+00, float 3.500000e+00>, ptr %memory0.field, align 16
  %memory1.base.field = getelementptr inbounds nuw %astra.struct.1, ptr %storage0, i32 0, i32 0
  %memory1.field = getelementptr inbounds nuw %astra.struct.0, ptr %memory1.base.field, i32 0, i32 1
  store <8 x i16> <i16 1, i16 2, i16 3, i16 4, i16 5, i16 6, i16 7, i16 8>, ptr %memory1.field, align 16
  %memory2.base.field = getelementptr inbounds nuw %astra.struct.1, ptr %storage0, i32 0, i32 0
  %memory2.field = getelementptr inbounds nuw %astra.struct.0, ptr %memory2.base.field, i32 0, i32 2
  store <4 x i1> <i1 true, i1 false, i1 true, i1 false>, ptr %memory2.field, align 1
  %memory3.base.field = getelementptr inbounds nuw %astra.struct.1, ptr %storage0, i32 0, i32 0
  %memory3.field = getelementptr inbounds nuw %astra.struct.0, ptr %memory3.base.field, i32 0, i32 0
  %v7 = load <4 x float>, ptr %memory3.field, align 16
  br label %b3

b1:                                               ; preds = %b5
  ret i32 1

b2:                                               ; preds = %b5
  %memory4.base.field = getelementptr inbounds nuw %astra.struct.1, ptr %storage0, i32 0, i32 0
  %memory4.field = getelementptr inbounds nuw %astra.struct.0, ptr %memory4.base.field, i32 0, i32 1
  %v14 = load <8 x i16>, ptr %memory4.field, align 16
  %v15 = insertelement <8 x i16> %v14, i16 42, i32 7
  %memory5.base.field = getelementptr inbounds nuw %astra.struct.1, ptr %storage0, i32 0, i32 0
  %memory5.field = getelementptr inbounds nuw %astra.struct.0, ptr %memory5.base.field, i32 0, i32 1
  store <8 x i16> %v15, ptr %memory5.field, align 16
  br label %b8

b3:                                               ; preds = %b0
  %v8 = fcmp oeq <4 x float> %v7, <float 5.000000e-01, float 1.500000e+00, float 2.500000e+00, float 3.500000e+00>
  %v9.lane0 = extractelement <4 x i1> %v8, i32 0
  %v9.lane1 = extractelement <4 x i1> %v8, i32 1
  %v9.reduce1 = and i1 %v9.lane0, %v9.lane1
  %v9.lane2 = extractelement <4 x i1> %v8, i32 2
  %v9.reduce2 = and i1 %v9.reduce1, %v9.lane2
  %v9.lane3 = extractelement <4 x i1> %v8, i32 3
  %v9 = and i1 %v9.reduce2, %v9.lane3
  %v10 = xor i1 %v9, true
  br i1 %v10, label %b5, label %b4

b4:                                               ; preds = %b3
  %memory11.base.field = getelementptr inbounds nuw %astra.struct.1, ptr %storage0, i32 0, i32 0
  %memory11.field = getelementptr inbounds nuw %astra.struct.0, ptr %memory11.base.field, i32 0, i32 0
  %v11 = load <4 x float>, ptr %memory11.field, align 16
  %v12 = extractelement <4 x float> %v11, i32 2
  %v13 = fcmp une float %v12, 2.500000e+00
  br label %b5

b5:                                               ; preds = %b4, %b3
  %v0 = phi i1 [ true, %b3 ], [ %v13, %b4 ]
  br i1 %v0, label %b1, label %b2

b6:                                               ; preds = %b10
  ret i32 2

b7:                                               ; preds = %b10
  call fastcc void @astra.fn.0(ptr %storage0, <8 x i16> <i16 1, i16 2, i16 3, i16 4, i16 5, i16 6, i16 7, i16 8>)
  br label %b13

b8:                                               ; preds = %b2
  %memory6.base.field = getelementptr inbounds nuw %astra.struct.1, ptr %storage0, i32 0, i32 0
  %memory6.field = getelementptr inbounds nuw %astra.struct.0, ptr %memory6.base.field, i32 0, i32 1
  %v16 = load <8 x i16>, ptr %memory6.field, align 16
  %v17 = extractelement <8 x i16> %v16, i32 7
  %v18 = icmp ne i16 %v17, 42
  br i1 %v18, label %b10, label %b9

b9:                                               ; preds = %b8
  %memory10.base.field = getelementptr inbounds nuw %astra.struct.1, ptr %storage0, i32 0, i32 0
  %memory10.field = getelementptr inbounds nuw %astra.struct.0, ptr %memory10.base.field, i32 0, i32 1
  %v19 = load <8 x i16>, ptr %memory10.field, align 16
  %v20 = extractelement <8 x i16> %v19, i32 0
  %v21 = icmp ne i16 %v20, 1
  br label %b10

b10:                                              ; preds = %b9, %b8
  %v1 = phi i1 [ true, %b8 ], [ %v21, %b9 ]
  br i1 %v1, label %b6, label %b7

b11:                                              ; preds = %b18
  ret i32 3

b12:                                              ; preds = %b18
  ret i32 0

b13:                                              ; preds = %b7
  br label %b14

b14:                                              ; preds = %b13
  %memory7.base.field = getelementptr inbounds nuw %astra.struct.1, ptr %storage0, i32 0, i32 0
  %memory7.field = getelementptr inbounds nuw %astra.struct.0, ptr %memory7.base.field, i32 0, i32 1
  %v23 = load <8 x i16>, ptr %memory7.field, align 16
  %v24 = icmp eq <8 x i16> %v23, <i16 1, i16 2, i16 3, i16 4, i16 5, i16 6, i16 7, i16 8>
  %v25.lane0 = extractelement <8 x i1> %v24, i32 0
  %v25.lane1 = extractelement <8 x i1> %v24, i32 1
  %v25.reduce1 = and i1 %v25.lane0, %v25.lane1
  %v25.lane2 = extractelement <8 x i1> %v24, i32 2
  %v25.reduce2 = and i1 %v25.reduce1, %v25.lane2
  %v25.lane3 = extractelement <8 x i1> %v24, i32 3
  %v25.reduce3 = and i1 %v25.reduce2, %v25.lane3
  %v25.lane4 = extractelement <8 x i1> %v24, i32 4
  %v25.reduce4 = and i1 %v25.reduce3, %v25.lane4
  %v25.lane5 = extractelement <8 x i1> %v24, i32 5
  %v25.reduce5 = and i1 %v25.reduce4, %v25.lane5
  %v25.lane6 = extractelement <8 x i1> %v24, i32 6
  %v25.reduce6 = and i1 %v25.reduce5, %v25.lane6
  %v25.lane7 = extractelement <8 x i1> %v24, i32 7
  %v25 = and i1 %v25.reduce6, %v25.lane7
  %v26 = xor i1 %v25, true
  br i1 %v26, label %b16, label %b15

b15:                                              ; preds = %b14
  %memory9.base.field = getelementptr inbounds nuw %astra.struct.1, ptr %storage0, i32 0, i32 0
  %memory9.field = getelementptr inbounds nuw %astra.struct.0, ptr %memory9.base.field, i32 0, i32 0
  %v27 = load <4 x float>, ptr %memory9.field, align 16
  %v28 = extractelement <4 x float> %v27, i32 2
  %v29 = fcmp une float %v28, 4.500000e+00
  br label %b16

b16:                                              ; preds = %b15, %b14
  %v2 = phi i1 [ true, %b14 ], [ %v29, %b15 ]
  br i1 %v2, label %b18, label %b17

b17:                                              ; preds = %b16
  %memory8.base.field = getelementptr inbounds nuw %astra.struct.1, ptr %storage0, i32 0, i32 0
  %memory8.field = getelementptr inbounds nuw %astra.struct.0, ptr %memory8.base.field, i32 0, i32 2
  %v30 = load <4 x i1>, ptr %memory8.field, align 1
  %v31.lane0 = extractelement <4 x i1> %v30, i32 0
  %v31.lane1 = extractelement <4 x i1> %v30, i32 1
  %v31.reduce1 = or i1 %v31.lane0, %v31.lane1
  %v31.lane2 = extractelement <4 x i1> %v30, i32 2
  %v31.reduce2 = or i1 %v31.reduce1, %v31.lane2
  %v31.lane3 = extractelement <4 x i1> %v30, i32 3
  %v31 = or i1 %v31.reduce2, %v31.lane3
  %v32 = xor i1 %v31, true
  br label %b18

b18:                                              ; preds = %b17, %b16
  %v3 = phi i1 [ true, %b16 ], [ %v32, %b17 ]
  br i1 %v3, label %b11, label %b12
}

; Function Attrs: cold noreturn nounwind memory(inaccessiblemem: write)
declare void @llvm.trap() #0

attributes #0 = { cold noreturn nounwind memory(inaccessiblemem: write) }
