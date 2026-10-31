; ModuleID = 'astra.scalar'
source_filename = "astra.scalar"

define internal fastcc i8 @astra.fn.0(i8 %p0, i8 %p1, i32 %p2) {
b0:
  %v3 = xor i8 %p0, -1
  %v4 = and i8 %v3, %p1
  %v5 = xor i8 %p0, %p1
  %v6 = or i8 %v4, %v5
  %v7.oversized = icmp sge i32 %p2, 8
  %v7.negative = icmp slt i32 %p2, 0
  %v7.invalid = or i1 %v7.negative, %v7.oversized
  br i1 %v7.invalid, label %v7.trap, label %v7.valid

v7.trap:                                          ; preds = %b0
  call void @llvm.trap()
  unreachable

v7.valid:                                         ; preds = %b0
  %v7.count = trunc i32 %p2 to i8
  %v7 = ashr i8 %v6, %v7.count
  ret i8 %v7
}

define internal fastcc <16 x i8> @astra.fn.1(<16 x i8> %p0, <16 x i8> %p1, i32 %p2) {
b0:
  %v3 = xor <16 x i8> %p0, splat (i8 -1)
  %v4 = and <16 x i8> %v3, %p1
  %v5 = xor <16 x i8> %p0, %p1
  %v6 = or <16 x i8> %v4, %v5
  %v7.oversized = icmp uge i32 %p2, 8
  br i1 %v7.oversized, label %v7.trap, label %v7.valid

v7.trap:                                          ; preds = %b0
  call void @llvm.trap()
  unreachable

v7.valid:                                         ; preds = %b0
  %v7.count = trunc i32 %p2 to i8
  %v7.count.seed = insertelement <16 x i8> zeroinitializer, i8 %v7.count, i32 0
  %v7.count.splat = shufflevector <16 x i8> %v7.count.seed, <16 x i8> %v7.count.seed, <16 x i32> zeroinitializer
  %v7 = ashr <16 x i8> %v6, %v7.count.splat
  ret <16 x i8> %v7
}

define internal fastcc <16 x i8> @astra.fn.2(<16 x i8> %p0, i8 %p1) {
b0:
  %v2.oversized = icmp sge i8 %p1, 8
  %v2.negative = icmp slt i8 %p1, 0
  %v2.invalid = or i1 %v2.negative, %v2.oversized
  br i1 %v2.invalid, label %v2.trap, label %v2.valid

v2.trap:                                          ; preds = %b0
  call void @llvm.trap()
  unreachable

v2.valid:                                         ; preds = %b0
  %v2.count.seed = insertelement <16 x i8> zeroinitializer, i8 %p1, i32 0
  %v2.count.splat = shufflevector <16 x i8> %v2.count.seed, <16 x i8> %v2.count.seed, <16 x i32> zeroinitializer
  %v2 = shl <16 x i8> %p0, %v2.count.splat
  ret <16 x i8> %v2
}

define internal fastcc i8 @astra.fn.3(i8 %p0, i8 %p1, i32 %p2) {
b0:
  %v3 = xor i8 %p0, -1
  %v4 = and i8 %v3, %p1
  %v5 = xor i8 %p0, %p1
  %v6 = or i8 %v4, %v5
  %v7.oversized = icmp sge i32 %p2, 8
  %v7.negative = icmp slt i32 %p2, 0
  %v7.invalid = or i1 %v7.negative, %v7.oversized
  br i1 %v7.invalid, label %v7.trap, label %v7.valid

v7.trap:                                          ; preds = %b0
  call void @llvm.trap()
  unreachable

v7.valid:                                         ; preds = %b0
  %v7.count = trunc i32 %p2 to i8
  %v7 = lshr i8 %v6, %v7.count
  ret i8 %v7
}

define internal fastcc <16 x i8> @astra.fn.4(<16 x i8> %p0, <16 x i8> %p1, i32 %p2) {
b0:
  %v3 = xor <16 x i8> %p0, splat (i8 -1)
  %v4 = and <16 x i8> %v3, %p1
  %v5 = xor <16 x i8> %p0, %p1
  %v6 = or <16 x i8> %v4, %v5
  %v7.oversized = icmp uge i32 %p2, 8
  br i1 %v7.oversized, label %v7.trap, label %v7.valid

v7.trap:                                          ; preds = %b0
  call void @llvm.trap()
  unreachable

v7.valid:                                         ; preds = %b0
  %v7.count = trunc i32 %p2 to i8
  %v7.count.seed = insertelement <16 x i8> zeroinitializer, i8 %v7.count, i32 0
  %v7.count.splat = shufflevector <16 x i8> %v7.count.seed, <16 x i8> %v7.count.seed, <16 x i32> zeroinitializer
  %v7 = lshr <16 x i8> %v6, %v7.count.splat
  ret <16 x i8> %v7
}

define internal fastcc <16 x i8> @astra.fn.5(<16 x i8> %p0, i8 %p1) {
b0:
  %v2.oversized = icmp sge i8 %p1, 8
  %v2.negative = icmp slt i8 %p1, 0
  %v2.invalid = or i1 %v2.negative, %v2.oversized
  br i1 %v2.invalid, label %v2.trap, label %v2.valid

v2.trap:                                          ; preds = %b0
  call void @llvm.trap()
  unreachable

v2.valid:                                         ; preds = %b0
  %v2.count.seed = insertelement <16 x i8> zeroinitializer, i8 %p1, i32 0
  %v2.count.splat = shufflevector <16 x i8> %v2.count.seed, <16 x i8> %v2.count.seed, <16 x i32> zeroinitializer
  %v2 = shl <16 x i8> %p0, %v2.count.splat
  ret <16 x i8> %v2
}

define internal fastcc i16 @astra.fn.6(i16 %p0, i16 %p1, i32 %p2) {
b0:
  %v3 = xor i16 %p0, -1
  %v4 = and i16 %v3, %p1
  %v5 = xor i16 %p0, %p1
  %v6 = or i16 %v4, %v5
  %v7.oversized = icmp sge i32 %p2, 16
  %v7.negative = icmp slt i32 %p2, 0
  %v7.invalid = or i1 %v7.negative, %v7.oversized
  br i1 %v7.invalid, label %v7.trap, label %v7.valid

v7.trap:                                          ; preds = %b0
  call void @llvm.trap()
  unreachable

v7.valid:                                         ; preds = %b0
  %v7.count = trunc i32 %p2 to i16
  %v7 = ashr i16 %v6, %v7.count
  ret i16 %v7
}

define internal fastcc <8 x i16> @astra.fn.7(<8 x i16> %p0, <8 x i16> %p1, i32 %p2) {
b0:
  %v3 = xor <8 x i16> %p0, splat (i16 -1)
  %v4 = and <8 x i16> %v3, %p1
  %v5 = xor <8 x i16> %p0, %p1
  %v6 = or <8 x i16> %v4, %v5
  %v7.oversized = icmp uge i32 %p2, 16
  br i1 %v7.oversized, label %v7.trap, label %v7.valid

v7.trap:                                          ; preds = %b0
  call void @llvm.trap()
  unreachable

v7.valid:                                         ; preds = %b0
  %v7.count = trunc i32 %p2 to i16
  %v7.count.seed = insertelement <8 x i16> zeroinitializer, i16 %v7.count, i32 0
  %v7.count.splat = shufflevector <8 x i16> %v7.count.seed, <8 x i16> %v7.count.seed, <8 x i32> zeroinitializer
  %v7 = ashr <8 x i16> %v6, %v7.count.splat
  ret <8 x i16> %v7
}

define internal fastcc <8 x i16> @astra.fn.8(<8 x i16> %p0, i8 %p1) {
b0:
  %v2.oversized = icmp sge i8 %p1, 16
  %v2.negative = icmp slt i8 %p1, 0
  %v2.invalid = or i1 %v2.negative, %v2.oversized
  br i1 %v2.invalid, label %v2.trap, label %v2.valid

v2.trap:                                          ; preds = %b0
  call void @llvm.trap()
  unreachable

v2.valid:                                         ; preds = %b0
  %v2.count = zext i8 %p1 to i16
  %v2.count.seed = insertelement <8 x i16> zeroinitializer, i16 %v2.count, i32 0
  %v2.count.splat = shufflevector <8 x i16> %v2.count.seed, <8 x i16> %v2.count.seed, <8 x i32> zeroinitializer
  %v2 = shl <8 x i16> %p0, %v2.count.splat
  ret <8 x i16> %v2
}

define internal fastcc i16 @astra.fn.9(i16 %p0, i16 %p1, i32 %p2) {
b0:
  %v3 = xor i16 %p0, -1
  %v4 = and i16 %v3, %p1
  %v5 = xor i16 %p0, %p1
  %v6 = or i16 %v4, %v5
  %v7.oversized = icmp sge i32 %p2, 16
  %v7.negative = icmp slt i32 %p2, 0
  %v7.invalid = or i1 %v7.negative, %v7.oversized
  br i1 %v7.invalid, label %v7.trap, label %v7.valid

v7.trap:                                          ; preds = %b0
  call void @llvm.trap()
  unreachable

v7.valid:                                         ; preds = %b0
  %v7.count = trunc i32 %p2 to i16
  %v7 = lshr i16 %v6, %v7.count
  ret i16 %v7
}

define internal fastcc <8 x i16> @astra.fn.10(<8 x i16> %p0, <8 x i16> %p1, i32 %p2) {
b0:
  %v3 = xor <8 x i16> %p0, splat (i16 -1)
  %v4 = and <8 x i16> %v3, %p1
  %v5 = xor <8 x i16> %p0, %p1
  %v6 = or <8 x i16> %v4, %v5
  %v7.oversized = icmp uge i32 %p2, 16
  br i1 %v7.oversized, label %v7.trap, label %v7.valid

v7.trap:                                          ; preds = %b0
  call void @llvm.trap()
  unreachable

v7.valid:                                         ; preds = %b0
  %v7.count = trunc i32 %p2 to i16
  %v7.count.seed = insertelement <8 x i16> zeroinitializer, i16 %v7.count, i32 0
  %v7.count.splat = shufflevector <8 x i16> %v7.count.seed, <8 x i16> %v7.count.seed, <8 x i32> zeroinitializer
  %v7 = lshr <8 x i16> %v6, %v7.count.splat
  ret <8 x i16> %v7
}

define internal fastcc <8 x i16> @astra.fn.11(<8 x i16> %p0, i8 %p1) {
b0:
  %v2.oversized = icmp sge i8 %p1, 16
  %v2.negative = icmp slt i8 %p1, 0
  %v2.invalid = or i1 %v2.negative, %v2.oversized
  br i1 %v2.invalid, label %v2.trap, label %v2.valid

v2.trap:                                          ; preds = %b0
  call void @llvm.trap()
  unreachable

v2.valid:                                         ; preds = %b0
  %v2.count = zext i8 %p1 to i16
  %v2.count.seed = insertelement <8 x i16> zeroinitializer, i16 %v2.count, i32 0
  %v2.count.splat = shufflevector <8 x i16> %v2.count.seed, <8 x i16> %v2.count.seed, <8 x i32> zeroinitializer
  %v2 = shl <8 x i16> %p0, %v2.count.splat
  ret <8 x i16> %v2
}

define internal fastcc i32 @astra.fn.12(i32 %p0, i32 %p1, i32 %p2) {
b0:
  %v3 = xor i32 %p0, -1
  %v4 = and i32 %v3, %p1
  %v5 = xor i32 %p0, %p1
  %v6 = or i32 %v4, %v5
  %v7.oversized = icmp sge i32 %p2, 32
  %v7.negative = icmp slt i32 %p2, 0
  %v7.invalid = or i1 %v7.negative, %v7.oversized
  br i1 %v7.invalid, label %v7.trap, label %v7.valid

v7.trap:                                          ; preds = %b0
  call void @llvm.trap()
  unreachable

v7.valid:                                         ; preds = %b0
  %v7 = ashr i32 %v6, %p2
  ret i32 %v7
}

define internal fastcc <4 x i32> @astra.fn.13(<4 x i32> %p0, <4 x i32> %p1, i32 %p2) {
b0:
  %v3 = xor <4 x i32> %p0, splat (i32 -1)
  %v4 = and <4 x i32> %v3, %p1
  %v5 = xor <4 x i32> %p0, %p1
  %v6 = or <4 x i32> %v4, %v5
  %v7.oversized = icmp uge i32 %p2, 32
  br i1 %v7.oversized, label %v7.trap, label %v7.valid

v7.trap:                                          ; preds = %b0
  call void @llvm.trap()
  unreachable

v7.valid:                                         ; preds = %b0
  %v7.count.seed = insertelement <4 x i32> zeroinitializer, i32 %p2, i32 0
  %v7.count.splat = shufflevector <4 x i32> %v7.count.seed, <4 x i32> %v7.count.seed, <4 x i32> zeroinitializer
  %v7 = ashr <4 x i32> %v6, %v7.count.splat
  ret <4 x i32> %v7
}

define internal fastcc <4 x i32> @astra.fn.14(<4 x i32> %p0, i8 %p1) {
b0:
  %v2.oversized = icmp sge i8 %p1, 32
  %v2.negative = icmp slt i8 %p1, 0
  %v2.invalid = or i1 %v2.negative, %v2.oversized
  br i1 %v2.invalid, label %v2.trap, label %v2.valid

v2.trap:                                          ; preds = %b0
  call void @llvm.trap()
  unreachable

v2.valid:                                         ; preds = %b0
  %v2.count = zext i8 %p1 to i32
  %v2.count.seed = insertelement <4 x i32> zeroinitializer, i32 %v2.count, i32 0
  %v2.count.splat = shufflevector <4 x i32> %v2.count.seed, <4 x i32> %v2.count.seed, <4 x i32> zeroinitializer
  %v2 = shl <4 x i32> %p0, %v2.count.splat
  ret <4 x i32> %v2
}

define internal fastcc i32 @astra.fn.15(i32 %p0, i32 %p1, i32 %p2) {
b0:
  %v3 = xor i32 %p0, -1
  %v4 = and i32 %v3, %p1
  %v5 = xor i32 %p0, %p1
  %v6 = or i32 %v4, %v5
  %v7.oversized = icmp sge i32 %p2, 32
  %v7.negative = icmp slt i32 %p2, 0
  %v7.invalid = or i1 %v7.negative, %v7.oversized
  br i1 %v7.invalid, label %v7.trap, label %v7.valid

v7.trap:                                          ; preds = %b0
  call void @llvm.trap()
  unreachable

v7.valid:                                         ; preds = %b0
  %v7 = lshr i32 %v6, %p2
  ret i32 %v7
}

define internal fastcc <4 x i32> @astra.fn.16(<4 x i32> %p0, <4 x i32> %p1, i32 %p2) {
b0:
  %v3 = xor <4 x i32> %p0, splat (i32 -1)
  %v4 = and <4 x i32> %v3, %p1
  %v5 = xor <4 x i32> %p0, %p1
  %v6 = or <4 x i32> %v4, %v5
  %v7.oversized = icmp uge i32 %p2, 32
  br i1 %v7.oversized, label %v7.trap, label %v7.valid

v7.trap:                                          ; preds = %b0
  call void @llvm.trap()
  unreachable

v7.valid:                                         ; preds = %b0
  %v7.count.seed = insertelement <4 x i32> zeroinitializer, i32 %p2, i32 0
  %v7.count.splat = shufflevector <4 x i32> %v7.count.seed, <4 x i32> %v7.count.seed, <4 x i32> zeroinitializer
  %v7 = lshr <4 x i32> %v6, %v7.count.splat
  ret <4 x i32> %v7
}

define internal fastcc <4 x i32> @astra.fn.17(<4 x i32> %p0, i8 %p1) {
b0:
  %v2.oversized = icmp sge i8 %p1, 32
  %v2.negative = icmp slt i8 %p1, 0
  %v2.invalid = or i1 %v2.negative, %v2.oversized
  br i1 %v2.invalid, label %v2.trap, label %v2.valid

v2.trap:                                          ; preds = %b0
  call void @llvm.trap()
  unreachable

v2.valid:                                         ; preds = %b0
  %v2.count = zext i8 %p1 to i32
  %v2.count.seed = insertelement <4 x i32> zeroinitializer, i32 %v2.count, i32 0
  %v2.count.splat = shufflevector <4 x i32> %v2.count.seed, <4 x i32> %v2.count.seed, <4 x i32> zeroinitializer
  %v2 = shl <4 x i32> %p0, %v2.count.splat
  ret <4 x i32> %v2
}

define internal fastcc i1 @astra.fn.18(i1 %p0, i1 %p1) {
b0:
  %v2 = and i1 %p0, %p1
  %v3 = xor i1 %p0, %p1
  %v4 = or i1 %v2, %v3
  ret i1 %v4
}

define internal fastcc <8 x i1> @astra.fn.19(<8 x i1> %p0, <8 x i1> %p1) {
b0:
  %v2 = and <8 x i1> %p0, %p1
  %v3 = xor <8 x i1> %p0, %p1
  %v4 = or <8 x i1> %v2, %v3
  ret <8 x i1> %v4
}

define internal fastcc i32 @astra.fn.20() {
b0:
  ret i32 0
}

; Function Attrs: cold noreturn nounwind memory(inaccessiblemem: write)
declare void @llvm.trap() #0

attributes #0 = { cold noreturn nounwind memory(inaccessiblemem: write) }
