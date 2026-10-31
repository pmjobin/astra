; ModuleID = 'astra.scalar'
source_filename = "astra.scalar"

define internal fastcc i16 @astra.fn.0(i8 %p0) {
b0:
  %v1 = sext i8 %p0 to i16
  ret i16 %v1
}

define internal fastcc i16 @astra.fn.1(i8 %p0) {
b0:
  %v1 = zext i8 %p0 to i16
  ret i16 %v1
}

define internal fastcc i8 @astra.fn.2(i16 %p0) {
b0:
  %v1 = trunc i16 %p0 to i8
  ret i8 %v1
}

define internal fastcc i8 @astra.fn.3(i8 %p0) {
b0:
  ret i8 %p0
}

define internal fastcc <8 x i16> @astra.fn.4(<8 x i8> %p0) {
b0:
  %v1 = sext <8 x i8> %p0 to <8 x i16>
  ret <8 x i16> %v1
}

define internal fastcc <8 x i16> @astra.fn.5(<8 x i8> %p0) {
b0:
  %v1 = zext <8 x i8> %p0 to <8 x i16>
  ret <8 x i16> %v1
}

define internal fastcc <8 x i8> @astra.fn.6(<8 x i16> %p0) {
b0:
  %v1 = trunc <8 x i16> %p0 to <8 x i8>
  ret <8 x i8> %v1
}

define internal fastcc <16 x i8> @astra.fn.7(<16 x i8> %p0) {
b0:
  ret <16 x i8> %p0
}

define internal fastcc i16 @astra.fn.8(i8 %p0) {
b0:
  %v1 = sext i8 %p0 to i16
  ret i16 %v1
}

define internal fastcc i16 @astra.fn.9(i8 %p0) {
b0:
  %v1 = zext i8 %p0 to i16
  ret i16 %v1
}

define internal fastcc i32 @astra.fn.10(i8 %p0) {
b0:
  %v1 = sext i8 %p0 to i16
  %v2 = sext i16 %v1 to i32
  ret i32 %v2
}

define internal fastcc i32 @astra.fn.11() {
b0:
  ret i32 0
}
