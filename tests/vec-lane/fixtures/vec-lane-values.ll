; ModuleID = 'astra.scalar'
source_filename = "astra.scalar"

define internal fastcc <4 x i16> @astra.fn.0(i16 %p0, <4 x i1> %p1) {
b0:
  %v2.seed = insertelement <4 x i16> zeroinitializer, i16 %p0, i32 0
  %v2 = shufflevector <4 x i16> %v2.seed, <4 x i16> %v2.seed, <4 x i32> zeroinitializer
  %v3 = extractelement <4 x i16> %v2, i32 2
  %v4 = insertelement <4 x i16> %v2, i16 %v3, i32 1
  %v5 = shufflevector <4 x i16> %v4, <4 x i16> %v4, <4 x i32> <i32 3, i32 2, i32 1, i32 0>
  %v6 = select <4 x i1> %p1, <4 x i16> %v5, <4 x i16> %v5
  ret <4 x i16> %v6
}

define internal fastcc i32 @astra.fn.1() {
b0:
  %v2 = call fastcc <4 x i16> @astra.fn.0(i16 7, <4 x i1> splat (i1 true))
  %v3 = icmp eq <4 x i16> %v2, splat (i16 7)
  %v4.lane0 = extractelement <4 x i1> %v3, i32 0
  %v4.lane1 = extractelement <4 x i1> %v3, i32 1
  %v4.reduce1 = and i1 %v4.lane0, %v4.lane1
  %v4.lane2 = extractelement <4 x i1> %v3, i32 2
  %v4.reduce2 = and i1 %v4.reduce1, %v4.lane2
  %v4.lane3 = extractelement <4 x i1> %v3, i32 3
  %v4 = and i1 %v4.reduce2, %v4.lane3
  %v5 = xor i1 %v4, true
  br i1 %v5, label %b1, label %b2

b1:                                               ; preds = %b0
  ret i32 1

b2:                                               ; preds = %b0
  ret i32 0
}
