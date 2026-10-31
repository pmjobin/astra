; ModuleID = 'astra.scalar'
source_filename = "astra.scalar"

define internal fastcc i8 @astra.fn.0(i8 %p0, i8 %p1) {
b0:
  %v2 = call i8 @llvm.sadd.sat.i8(i8 %p0, i8 %p1)
  ret i8 %v2
}

define internal fastcc i8 @astra.fn.1(i8 %p0, i8 %p1) {
b0:
  %v2 = call i8 @llvm.usub.sat.i8(i8 %p0, i8 %p1)
  ret i8 %v2
}

define internal fastcc <16 x i8> @astra.fn.2(<16 x i8> %p0, <16 x i8> %p1) {
b0:
  %v2 = call <16 x i8> @llvm.sadd.sat.v16i8(<16 x i8> %p0, <16 x i8> %p1)
  ret <16 x i8> %v2
}

define internal fastcc <16 x i8> @astra.fn.3(<16 x i8> %p0, <16 x i8> %p1) {
b0:
  %v2 = call <16 x i8> @llvm.uadd.sat.v16i8(<16 x i8> %p0, <16 x i8> %p1)
  ret <16 x i8> %v2
}

define internal fastcc <8 x i16> @astra.fn.4(<8 x i16> %p0, <8 x i16> %p1) {
b0:
  %v2 = call <8 x i16> @llvm.sadd.sat.v8i16(<8 x i16> %p0, <8 x i16> %p1)
  %v3 = call <8 x i16> @llvm.ssub.sat.v8i16(<8 x i16> %v2, <8 x i16> %p1)
  ret <8 x i16> %v3
}

define internal fastcc <8 x i16> @astra.fn.5(<8 x i16> %p0, <8 x i16> %p1) {
b0:
  %v2 = call <8 x i16> @llvm.uadd.sat.v8i16(<8 x i16> %p0, <8 x i16> %p1)
  %v3 = call <8 x i16> @llvm.usub.sat.v8i16(<8 x i16> %v2, <8 x i16> %p1)
  ret <8 x i16> %v3
}

define internal fastcc <8 x i16> @astra.fn.6(<16 x i8> %p0) {
b0:
  %v1.half = shufflevector <16 x i8> %p0, <16 x i8> %p0, <8 x i32> <i32 0, i32 1, i32 2, i32 3, i32 4, i32 5, i32 6, i32 7>
  %v1 = sext <8 x i8> %v1.half to <8 x i16>
  ret <8 x i16> %v1
}

define internal fastcc <8 x i16> @astra.fn.7(<16 x i8> %p0) {
b0:
  %v1.half = shufflevector <16 x i8> %p0, <16 x i8> %p0, <8 x i32> <i32 8, i32 9, i32 10, i32 11, i32 12, i32 13, i32 14, i32 15>
  %v1 = zext <8 x i8> %v1.half to <8 x i16>
  ret <8 x i16> %v1
}

define internal fastcc <16 x i8> @astra.fn.8(<8 x i16> %p0, <8 x i16> %p1) {
b0:
  %v2.first = trunc <8 x i16> %p0 to <8 x i8>
  %v2.second = trunc <8 x i16> %p1 to <8 x i8>
  %v2 = shufflevector <8 x i8> %v2.first, <8 x i8> %v2.second, <16 x i32> <i32 0, i32 1, i32 2, i32 3, i32 4, i32 5, i32 6, i32 7, i32 8, i32 9, i32 10, i32 11, i32 12, i32 13, i32 14, i32 15>
  ret <16 x i8> %v2
}

define internal fastcc <16 x i8> @astra.fn.9(<8 x i16> %p0, <8 x i16> %p1) {
b0:
  %v2.first.below = icmp slt <8 x i16> %p0, zeroinitializer
  %v2.first.min = select <8 x i1> %v2.first.below, <8 x i16> zeroinitializer, <8 x i16> %p0
  %v2.first.above = icmp sgt <8 x i16> %v2.first.min, splat (i16 255)
  %v2.first.max = select <8 x i1> %v2.first.above, <8 x i16> splat (i16 255), <8 x i16> %v2.first.min
  %v2.first = trunc <8 x i16> %v2.first.max to <8 x i8>
  %v2.second.below = icmp slt <8 x i16> %p1, zeroinitializer
  %v2.second.min = select <8 x i1> %v2.second.below, <8 x i16> zeroinitializer, <8 x i16> %p1
  %v2.second.above = icmp sgt <8 x i16> %v2.second.min, splat (i16 255)
  %v2.second.max = select <8 x i1> %v2.second.above, <8 x i16> splat (i16 255), <8 x i16> %v2.second.min
  %v2.second = trunc <8 x i16> %v2.second.max to <8 x i8>
  %v2 = shufflevector <8 x i8> %v2.first, <8 x i8> %v2.second, <16 x i32> <i32 0, i32 1, i32 2, i32 3, i32 4, i32 5, i32 6, i32 7, i32 8, i32 9, i32 10, i32 11, i32 12, i32 13, i32 14, i32 15>
  ret <16 x i8> %v2
}

define internal fastcc <16 x i8> @astra.fn.10(<8 x i16> %p0, <8 x i16> %p1) {
b0:
  %v2.first.below = icmp slt <8 x i16> %p0, splat (i16 -128)
  %v2.first.min = select <8 x i1> %v2.first.below, <8 x i16> splat (i16 -128), <8 x i16> %p0
  %v2.first.above = icmp sgt <8 x i16> %v2.first.min, splat (i16 127)
  %v2.first.max = select <8 x i1> %v2.first.above, <8 x i16> splat (i16 127), <8 x i16> %v2.first.min
  %v2.first = trunc <8 x i16> %v2.first.max to <8 x i8>
  %v2.second.below = icmp slt <8 x i16> %p1, splat (i16 -128)
  %v2.second.min = select <8 x i1> %v2.second.below, <8 x i16> splat (i16 -128), <8 x i16> %p1
  %v2.second.above = icmp sgt <8 x i16> %v2.second.min, splat (i16 127)
  %v2.second.max = select <8 x i1> %v2.second.above, <8 x i16> splat (i16 127), <8 x i16> %v2.second.min
  %v2.second = trunc <8 x i16> %v2.second.max to <8 x i8>
  %v2 = shufflevector <8 x i8> %v2.first, <8 x i8> %v2.second, <16 x i32> <i32 0, i32 1, i32 2, i32 3, i32 4, i32 5, i32 6, i32 7, i32 8, i32 9, i32 10, i32 11, i32 12, i32 13, i32 14, i32 15>
  ret <16 x i8> %v2
}

define internal fastcc <16 x i8> @astra.fn.11(<8 x i16> %p0, <8 x i16> %p1) {
b0:
  %v2.first.above = icmp ugt <8 x i16> %p0, splat (i16 127)
  %v2.first.max = select <8 x i1> %v2.first.above, <8 x i16> splat (i16 127), <8 x i16> %p0
  %v2.first = trunc <8 x i16> %v2.first.max to <8 x i8>
  %v2.second.above = icmp ugt <8 x i16> %p1, splat (i16 127)
  %v2.second.max = select <8 x i1> %v2.second.above, <8 x i16> splat (i16 127), <8 x i16> %p1
  %v2.second = trunc <8 x i16> %v2.second.max to <8 x i8>
  %v2 = shufflevector <8 x i8> %v2.first, <8 x i8> %v2.second, <16 x i32> <i32 0, i32 1, i32 2, i32 3, i32 4, i32 5, i32 6, i32 7, i32 8, i32 9, i32 10, i32 11, i32 12, i32 13, i32 14, i32 15>
  ret <16 x i8> %v2
}

define internal fastcc <16 x i8> @astra.fn.12(<16 x i8> %p0, <16 x i8> %p1) {
b0:
  %v2 = shufflevector <16 x i8> %p0, <16 x i8> %p1, <16 x i32> <i32 0, i32 16, i32 1, i32 17, i32 2, i32 18, i32 3, i32 19, i32 4, i32 20, i32 5, i32 21, i32 6, i32 22, i32 7, i32 23>
  ret <16 x i8> %v2
}

define internal fastcc <16 x i8> @astra.fn.13(<16 x i8> %p0, <16 x i8> %p1) {
b0:
  %v2 = shufflevector <16 x i8> %p0, <16 x i8> %p1, <16 x i32> <i32 8, i32 24, i32 9, i32 25, i32 10, i32 26, i32 11, i32 27, i32 12, i32 28, i32 13, i32 29, i32 14, i32 30, i32 15, i32 31>
  ret <16 x i8> %v2
}

define internal fastcc <4 x float> @astra.fn.14(<4 x float> %p0, <4 x float> %p1) {
b0:
  %v2 = shufflevector <4 x float> %p0, <4 x float> %p1, <4 x i32> <i32 2, i32 6, i32 3, i32 7>
  ret <4 x float> %v2
}

define internal fastcc <8 x i1> @astra.fn.15(<8 x i1> %p0, <8 x i1> %p1) {
b0:
  %v2 = shufflevector <8 x i1> %p0, <8 x i1> %p1, <8 x i32> <i32 0, i32 8, i32 1, i32 9, i32 2, i32 10, i32 3, i32 11>
  ret <8 x i1> %v2
}

define internal fastcc i32 @astra.fn.16() {
b0:
  ret i32 0
}

; Function Attrs: nocallback nocreateundeforpoison nofree nosync nounwind speculatable willreturn memory(none)
declare i8 @llvm.sadd.sat.i8(i8, i8) #0

; Function Attrs: nocallback nocreateundeforpoison nofree nosync nounwind speculatable willreturn memory(none)
declare i8 @llvm.usub.sat.i8(i8, i8) #0

; Function Attrs: nocallback nocreateundeforpoison nofree nosync nounwind speculatable willreturn memory(none)
declare <16 x i8> @llvm.sadd.sat.v16i8(<16 x i8>, <16 x i8>) #0

; Function Attrs: nocallback nocreateundeforpoison nofree nosync nounwind speculatable willreturn memory(none)
declare <16 x i8> @llvm.uadd.sat.v16i8(<16 x i8>, <16 x i8>) #0

; Function Attrs: nocallback nocreateundeforpoison nofree nosync nounwind speculatable willreturn memory(none)
declare <8 x i16> @llvm.sadd.sat.v8i16(<8 x i16>, <8 x i16>) #0

; Function Attrs: nocallback nocreateundeforpoison nofree nosync nounwind speculatable willreturn memory(none)
declare <8 x i16> @llvm.ssub.sat.v8i16(<8 x i16>, <8 x i16>) #0

; Function Attrs: nocallback nocreateundeforpoison nofree nosync nounwind speculatable willreturn memory(none)
declare <8 x i16> @llvm.uadd.sat.v8i16(<8 x i16>, <8 x i16>) #0

; Function Attrs: nocallback nocreateundeforpoison nofree nosync nounwind speculatable willreturn memory(none)
declare <8 x i16> @llvm.usub.sat.v8i16(<8 x i16>, <8 x i16>) #0

attributes #0 = { nocallback nocreateundeforpoison nofree nosync nounwind speculatable willreturn memory(none) }
