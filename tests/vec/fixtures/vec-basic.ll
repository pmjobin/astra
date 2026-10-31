; ModuleID = 'astra.scalar'
source_filename = "astra.scalar"

define internal fastcc <4 x i32> @astra.fn.0(<4 x i32> %p0, <4 x i32> %p1) {
b0:
  %v3 = add <4 x i32> %p0, %p1
  ret <4 x i32> %v3
}

define internal fastcc <4 x i32> @astra.fn.1(i32 %p0, i32 %p1, i32 %p2, i32 %p3) {
b0:
  %v4.lane0 = insertelement <4 x i32> zeroinitializer, i32 %p0, i32 0
  %v4.lane1 = insertelement <4 x i32> %v4.lane0, i32 %p1, i32 1
  %v4.lane2 = insertelement <4 x i32> %v4.lane1, i32 %p2, i32 2
  %v4 = insertelement <4 x i32> %v4.lane2, i32 %p3, i32 3
  ret <4 x i32> %v4
}

define internal fastcc i32 @astra.fn.2() {
b0:
  %v1 = call fastcc <4 x i32> @astra.fn.1(i32 5, i32 6, i32 7, i32 8)
  %v3 = call fastcc <4 x i32> @astra.fn.0(<4 x i32> <i32 1, i32 2, i32 3, i32 4>, <4 x i32> %v1)
  %v4 = icmp eq <4 x i32> %v3, <i32 6, i32 8, i32 10, i32 12>
  %v5.lane0 = extractelement <4 x i1> %v4, i32 0
  %v5.lane1 = extractelement <4 x i1> %v4, i32 1
  %v5.reduce1 = and i1 %v5.lane0, %v5.lane1
  %v5.lane2 = extractelement <4 x i1> %v4, i32 2
  %v5.reduce2 = and i1 %v5.reduce1, %v5.lane2
  %v5.lane3 = extractelement <4 x i1> %v4, i32 3
  %v5 = and i1 %v5.reduce2, %v5.lane3
  br i1 %v5, label %b1, label %b2

b1:                                               ; preds = %b0
  ret i32 0

b2:                                               ; preds = %b0
  ret i32 1
}
