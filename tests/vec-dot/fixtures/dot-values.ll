; ModuleID = 'astra.scalar'
source_filename = "astra.scalar"

define internal fastcc i16 @astra.fn.0(<16 x i8> %p0, <16 x i8> %p1) {
b0:
  %v2.a = sext <16 x i8> %p0 to <16 x i16>
  %v2.b = sext <16 x i8> %p1 to <16 x i16>
  %v2.products = mul <16 x i16> %v2.a, %v2.b
  %v2.lane0 = extractelement <16 x i16> %v2.products, i32 0
  %v2.acc0 = add i16 0, %v2.lane0
  %v2.lane1 = extractelement <16 x i16> %v2.products, i32 1
  %v2.acc1 = add i16 %v2.acc0, %v2.lane1
  %v2.lane2 = extractelement <16 x i16> %v2.products, i32 2
  %v2.acc2 = add i16 %v2.acc1, %v2.lane2
  %v2.lane3 = extractelement <16 x i16> %v2.products, i32 3
  %v2.acc3 = add i16 %v2.acc2, %v2.lane3
  %v2.lane4 = extractelement <16 x i16> %v2.products, i32 4
  %v2.acc4 = add i16 %v2.acc3, %v2.lane4
  %v2.lane5 = extractelement <16 x i16> %v2.products, i32 5
  %v2.acc5 = add i16 %v2.acc4, %v2.lane5
  %v2.lane6 = extractelement <16 x i16> %v2.products, i32 6
  %v2.acc6 = add i16 %v2.acc5, %v2.lane6
  %v2.lane7 = extractelement <16 x i16> %v2.products, i32 7
  %v2.acc7 = add i16 %v2.acc6, %v2.lane7
  %v2.lane8 = extractelement <16 x i16> %v2.products, i32 8
  %v2.acc8 = add i16 %v2.acc7, %v2.lane8
  %v2.lane9 = extractelement <16 x i16> %v2.products, i32 9
  %v2.acc9 = add i16 %v2.acc8, %v2.lane9
  %v2.lane10 = extractelement <16 x i16> %v2.products, i32 10
  %v2.acc10 = add i16 %v2.acc9, %v2.lane10
  %v2.lane11 = extractelement <16 x i16> %v2.products, i32 11
  %v2.acc11 = add i16 %v2.acc10, %v2.lane11
  %v2.lane12 = extractelement <16 x i16> %v2.products, i32 12
  %v2.acc12 = add i16 %v2.acc11, %v2.lane12
  %v2.lane13 = extractelement <16 x i16> %v2.products, i32 13
  %v2.acc13 = add i16 %v2.acc12, %v2.lane13
  %v2.lane14 = extractelement <16 x i16> %v2.products, i32 14
  %v2.acc14 = add i16 %v2.acc13, %v2.lane14
  %v2.lane15 = extractelement <16 x i16> %v2.products, i32 15
  %v2 = add i16 %v2.acc14, %v2.lane15
  ret i16 %v2
}

define internal fastcc i32 @astra.fn.1(<16 x i8> %p0, <16 x i8> %p1) {
b0:
  %v2.a = sext <16 x i8> %p0 to <16 x i32>
  %v2.b = sext <16 x i8> %p1 to <16 x i32>
  %v2.products = mul <16 x i32> %v2.a, %v2.b
  %v2.lane0 = extractelement <16 x i32> %v2.products, i32 0
  %v2.acc0 = add i32 0, %v2.lane0
  %v2.lane1 = extractelement <16 x i32> %v2.products, i32 1
  %v2.acc1 = add i32 %v2.acc0, %v2.lane1
  %v2.lane2 = extractelement <16 x i32> %v2.products, i32 2
  %v2.acc2 = add i32 %v2.acc1, %v2.lane2
  %v2.lane3 = extractelement <16 x i32> %v2.products, i32 3
  %v2.acc3 = add i32 %v2.acc2, %v2.lane3
  %v2.lane4 = extractelement <16 x i32> %v2.products, i32 4
  %v2.acc4 = add i32 %v2.acc3, %v2.lane4
  %v2.lane5 = extractelement <16 x i32> %v2.products, i32 5
  %v2.acc5 = add i32 %v2.acc4, %v2.lane5
  %v2.lane6 = extractelement <16 x i32> %v2.products, i32 6
  %v2.acc6 = add i32 %v2.acc5, %v2.lane6
  %v2.lane7 = extractelement <16 x i32> %v2.products, i32 7
  %v2.acc7 = add i32 %v2.acc6, %v2.lane7
  %v2.lane8 = extractelement <16 x i32> %v2.products, i32 8
  %v2.acc8 = add i32 %v2.acc7, %v2.lane8
  %v2.lane9 = extractelement <16 x i32> %v2.products, i32 9
  %v2.acc9 = add i32 %v2.acc8, %v2.lane9
  %v2.lane10 = extractelement <16 x i32> %v2.products, i32 10
  %v2.acc10 = add i32 %v2.acc9, %v2.lane10
  %v2.lane11 = extractelement <16 x i32> %v2.products, i32 11
  %v2.acc11 = add i32 %v2.acc10, %v2.lane11
  %v2.lane12 = extractelement <16 x i32> %v2.products, i32 12
  %v2.acc12 = add i32 %v2.acc11, %v2.lane12
  %v2.lane13 = extractelement <16 x i32> %v2.products, i32 13
  %v2.acc13 = add i32 %v2.acc12, %v2.lane13
  %v2.lane14 = extractelement <16 x i32> %v2.products, i32 14
  %v2.acc14 = add i32 %v2.acc13, %v2.lane14
  %v2.lane15 = extractelement <16 x i32> %v2.products, i32 15
  %v2 = add i32 %v2.acc14, %v2.lane15
  ret i32 %v2
}

define internal fastcc i16 @astra.fn.2(<16 x i8> %p0, <16 x i8> %p1) {
b0:
  %v2.a = zext <16 x i8> %p0 to <16 x i16>
  %v2.b = zext <16 x i8> %p1 to <16 x i16>
  %v2.products = mul <16 x i16> %v2.a, %v2.b
  %v2.lane0 = extractelement <16 x i16> %v2.products, i32 0
  %v2.acc0 = add i16 0, %v2.lane0
  %v2.lane1 = extractelement <16 x i16> %v2.products, i32 1
  %v2.acc1 = add i16 %v2.acc0, %v2.lane1
  %v2.lane2 = extractelement <16 x i16> %v2.products, i32 2
  %v2.acc2 = add i16 %v2.acc1, %v2.lane2
  %v2.lane3 = extractelement <16 x i16> %v2.products, i32 3
  %v2.acc3 = add i16 %v2.acc2, %v2.lane3
  %v2.lane4 = extractelement <16 x i16> %v2.products, i32 4
  %v2.acc4 = add i16 %v2.acc3, %v2.lane4
  %v2.lane5 = extractelement <16 x i16> %v2.products, i32 5
  %v2.acc5 = add i16 %v2.acc4, %v2.lane5
  %v2.lane6 = extractelement <16 x i16> %v2.products, i32 6
  %v2.acc6 = add i16 %v2.acc5, %v2.lane6
  %v2.lane7 = extractelement <16 x i16> %v2.products, i32 7
  %v2.acc7 = add i16 %v2.acc6, %v2.lane7
  %v2.lane8 = extractelement <16 x i16> %v2.products, i32 8
  %v2.acc8 = add i16 %v2.acc7, %v2.lane8
  %v2.lane9 = extractelement <16 x i16> %v2.products, i32 9
  %v2.acc9 = add i16 %v2.acc8, %v2.lane9
  %v2.lane10 = extractelement <16 x i16> %v2.products, i32 10
  %v2.acc10 = add i16 %v2.acc9, %v2.lane10
  %v2.lane11 = extractelement <16 x i16> %v2.products, i32 11
  %v2.acc11 = add i16 %v2.acc10, %v2.lane11
  %v2.lane12 = extractelement <16 x i16> %v2.products, i32 12
  %v2.acc12 = add i16 %v2.acc11, %v2.lane12
  %v2.lane13 = extractelement <16 x i16> %v2.products, i32 13
  %v2.acc13 = add i16 %v2.acc12, %v2.lane13
  %v2.lane14 = extractelement <16 x i16> %v2.products, i32 14
  %v2.acc14 = add i16 %v2.acc13, %v2.lane14
  %v2.lane15 = extractelement <16 x i16> %v2.products, i32 15
  %v2 = add i16 %v2.acc14, %v2.lane15
  ret i16 %v2
}

define internal fastcc i32 @astra.fn.3(<16 x i8> %p0, <16 x i8> %p1) {
b0:
  %v2.a = zext <16 x i8> %p0 to <16 x i32>
  %v2.b = zext <16 x i8> %p1 to <16 x i32>
  %v2.products = mul <16 x i32> %v2.a, %v2.b
  %v2.lane0 = extractelement <16 x i32> %v2.products, i32 0
  %v2.acc0 = add i32 0, %v2.lane0
  %v2.lane1 = extractelement <16 x i32> %v2.products, i32 1
  %v2.acc1 = add i32 %v2.acc0, %v2.lane1
  %v2.lane2 = extractelement <16 x i32> %v2.products, i32 2
  %v2.acc2 = add i32 %v2.acc1, %v2.lane2
  %v2.lane3 = extractelement <16 x i32> %v2.products, i32 3
  %v2.acc3 = add i32 %v2.acc2, %v2.lane3
  %v2.lane4 = extractelement <16 x i32> %v2.products, i32 4
  %v2.acc4 = add i32 %v2.acc3, %v2.lane4
  %v2.lane5 = extractelement <16 x i32> %v2.products, i32 5
  %v2.acc5 = add i32 %v2.acc4, %v2.lane5
  %v2.lane6 = extractelement <16 x i32> %v2.products, i32 6
  %v2.acc6 = add i32 %v2.acc5, %v2.lane6
  %v2.lane7 = extractelement <16 x i32> %v2.products, i32 7
  %v2.acc7 = add i32 %v2.acc6, %v2.lane7
  %v2.lane8 = extractelement <16 x i32> %v2.products, i32 8
  %v2.acc8 = add i32 %v2.acc7, %v2.lane8
  %v2.lane9 = extractelement <16 x i32> %v2.products, i32 9
  %v2.acc9 = add i32 %v2.acc8, %v2.lane9
  %v2.lane10 = extractelement <16 x i32> %v2.products, i32 10
  %v2.acc10 = add i32 %v2.acc9, %v2.lane10
  %v2.lane11 = extractelement <16 x i32> %v2.products, i32 11
  %v2.acc11 = add i32 %v2.acc10, %v2.lane11
  %v2.lane12 = extractelement <16 x i32> %v2.products, i32 12
  %v2.acc12 = add i32 %v2.acc11, %v2.lane12
  %v2.lane13 = extractelement <16 x i32> %v2.products, i32 13
  %v2.acc13 = add i32 %v2.acc12, %v2.lane13
  %v2.lane14 = extractelement <16 x i32> %v2.products, i32 14
  %v2.acc14 = add i32 %v2.acc13, %v2.lane14
  %v2.lane15 = extractelement <16 x i32> %v2.products, i32 15
  %v2 = add i32 %v2.acc14, %v2.lane15
  ret i32 %v2
}

define internal fastcc i32 @astra.fn.4(<8 x i16> %p0, <8 x i16> %p1) {
b0:
  %v2.a = sext <8 x i16> %p0 to <8 x i32>
  %v2.b = sext <8 x i16> %p1 to <8 x i32>
  %v2.products = mul <8 x i32> %v2.a, %v2.b
  %v2.lane0 = extractelement <8 x i32> %v2.products, i32 0
  %v2.acc0 = add i32 0, %v2.lane0
  %v2.lane1 = extractelement <8 x i32> %v2.products, i32 1
  %v2.acc1 = add i32 %v2.acc0, %v2.lane1
  %v2.lane2 = extractelement <8 x i32> %v2.products, i32 2
  %v2.acc2 = add i32 %v2.acc1, %v2.lane2
  %v2.lane3 = extractelement <8 x i32> %v2.products, i32 3
  %v2.acc3 = add i32 %v2.acc2, %v2.lane3
  %v2.lane4 = extractelement <8 x i32> %v2.products, i32 4
  %v2.acc4 = add i32 %v2.acc3, %v2.lane4
  %v2.lane5 = extractelement <8 x i32> %v2.products, i32 5
  %v2.acc5 = add i32 %v2.acc4, %v2.lane5
  %v2.lane6 = extractelement <8 x i32> %v2.products, i32 6
  %v2.acc6 = add i32 %v2.acc5, %v2.lane6
  %v2.lane7 = extractelement <8 x i32> %v2.products, i32 7
  %v2 = add i32 %v2.acc6, %v2.lane7
  ret i32 %v2
}

define internal fastcc i32 @astra.fn.5(<8 x i16> %p0, <8 x i16> %p1) {
b0:
  %v2.a = zext <8 x i16> %p0 to <8 x i32>
  %v2.b = zext <8 x i16> %p1 to <8 x i32>
  %v2.products = mul <8 x i32> %v2.a, %v2.b
  %v2.lane0 = extractelement <8 x i32> %v2.products, i32 0
  %v2.acc0 = add i32 0, %v2.lane0
  %v2.lane1 = extractelement <8 x i32> %v2.products, i32 1
  %v2.acc1 = add i32 %v2.acc0, %v2.lane1
  %v2.lane2 = extractelement <8 x i32> %v2.products, i32 2
  %v2.acc2 = add i32 %v2.acc1, %v2.lane2
  %v2.lane3 = extractelement <8 x i32> %v2.products, i32 3
  %v2.acc3 = add i32 %v2.acc2, %v2.lane3
  %v2.lane4 = extractelement <8 x i32> %v2.products, i32 4
  %v2.acc4 = add i32 %v2.acc3, %v2.lane4
  %v2.lane5 = extractelement <8 x i32> %v2.products, i32 5
  %v2.acc5 = add i32 %v2.acc4, %v2.lane5
  %v2.lane6 = extractelement <8 x i32> %v2.products, i32 6
  %v2.acc6 = add i32 %v2.acc5, %v2.lane6
  %v2.lane7 = extractelement <8 x i32> %v2.products, i32 7
  %v2 = add i32 %v2.acc6, %v2.lane7
  ret i32 %v2
}

define internal fastcc i32 @astra.fn.6(<4 x i32> %p0, <4 x i32> %p1) {
b0:
  %v2.products = mul <4 x i32> %p0, %p1
  %v2.lane0 = extractelement <4 x i32> %v2.products, i32 0
  %v2.acc0 = add i32 0, %v2.lane0
  %v2.lane1 = extractelement <4 x i32> %v2.products, i32 1
  %v2.acc1 = add i32 %v2.acc0, %v2.lane1
  %v2.lane2 = extractelement <4 x i32> %v2.products, i32 2
  %v2.acc2 = add i32 %v2.acc1, %v2.lane2
  %v2.lane3 = extractelement <4 x i32> %v2.products, i32 3
  %v2 = add i32 %v2.acc2, %v2.lane3
  ret i32 %v2
}

define internal fastcc i32 @astra.fn.7(<4 x i32> %p0, <4 x i32> %p1) {
b0:
  %v2.products = mul <4 x i32> %p0, %p1
  %v2.lane0 = extractelement <4 x i32> %v2.products, i32 0
  %v2.acc0 = add i32 0, %v2.lane0
  %v2.lane1 = extractelement <4 x i32> %v2.products, i32 1
  %v2.acc1 = add i32 %v2.acc0, %v2.lane1
  %v2.lane2 = extractelement <4 x i32> %v2.products, i32 2
  %v2.acc2 = add i32 %v2.acc1, %v2.lane2
  %v2.lane3 = extractelement <4 x i32> %v2.products, i32 3
  %v2 = add i32 %v2.acc2, %v2.lane3
  ret i32 %v2
}

define internal fastcc i16 @astra.fn.8(<16 x i8> %p0, <16 x i8> %p1) {
b0:
  %v2.a = sext <16 x i8> %p0 to <16 x i16>
  %v2.b = sext <16 x i8> %p1 to <16 x i16>
  %v2.products = mul <16 x i16> %v2.a, %v2.b
  %v2.lane0 = extractelement <16 x i16> %v2.products, i32 0
  %v2.acc0 = add i16 0, %v2.lane0
  %v2.lane1 = extractelement <16 x i16> %v2.products, i32 1
  %v2.acc1 = add i16 %v2.acc0, %v2.lane1
  %v2.lane2 = extractelement <16 x i16> %v2.products, i32 2
  %v2.acc2 = add i16 %v2.acc1, %v2.lane2
  %v2.lane3 = extractelement <16 x i16> %v2.products, i32 3
  %v2.acc3 = add i16 %v2.acc2, %v2.lane3
  %v2.lane4 = extractelement <16 x i16> %v2.products, i32 4
  %v2.acc4 = add i16 %v2.acc3, %v2.lane4
  %v2.lane5 = extractelement <16 x i16> %v2.products, i32 5
  %v2.acc5 = add i16 %v2.acc4, %v2.lane5
  %v2.lane6 = extractelement <16 x i16> %v2.products, i32 6
  %v2.acc6 = add i16 %v2.acc5, %v2.lane6
  %v2.lane7 = extractelement <16 x i16> %v2.products, i32 7
  %v2.acc7 = add i16 %v2.acc6, %v2.lane7
  %v2.lane8 = extractelement <16 x i16> %v2.products, i32 8
  %v2.acc8 = add i16 %v2.acc7, %v2.lane8
  %v2.lane9 = extractelement <16 x i16> %v2.products, i32 9
  %v2.acc9 = add i16 %v2.acc8, %v2.lane9
  %v2.lane10 = extractelement <16 x i16> %v2.products, i32 10
  %v2.acc10 = add i16 %v2.acc9, %v2.lane10
  %v2.lane11 = extractelement <16 x i16> %v2.products, i32 11
  %v2.acc11 = add i16 %v2.acc10, %v2.lane11
  %v2.lane12 = extractelement <16 x i16> %v2.products, i32 12
  %v2.acc12 = add i16 %v2.acc11, %v2.lane12
  %v2.lane13 = extractelement <16 x i16> %v2.products, i32 13
  %v2.acc13 = add i16 %v2.acc12, %v2.lane13
  %v2.lane14 = extractelement <16 x i16> %v2.products, i32 14
  %v2.acc14 = add i16 %v2.acc13, %v2.lane14
  %v2.lane15 = extractelement <16 x i16> %v2.products, i32 15
  %v2 = add i16 %v2.acc14, %v2.lane15
  ret i16 %v2
}

define internal fastcc i16 @astra.fn.9(<16 x i8> %p0, <16 x i8> %p1) {
b0:
  %v2.a = zext <16 x i8> %p0 to <16 x i16>
  %v2.b = zext <16 x i8> %p1 to <16 x i16>
  %v2.products = mul <16 x i16> %v2.a, %v2.b
  %v2.lane0 = extractelement <16 x i16> %v2.products, i32 0
  %v2.acc0 = add i16 0, %v2.lane0
  %v2.lane1 = extractelement <16 x i16> %v2.products, i32 1
  %v2.acc1 = add i16 %v2.acc0, %v2.lane1
  %v2.lane2 = extractelement <16 x i16> %v2.products, i32 2
  %v2.acc2 = add i16 %v2.acc1, %v2.lane2
  %v2.lane3 = extractelement <16 x i16> %v2.products, i32 3
  %v2.acc3 = add i16 %v2.acc2, %v2.lane3
  %v2.lane4 = extractelement <16 x i16> %v2.products, i32 4
  %v2.acc4 = add i16 %v2.acc3, %v2.lane4
  %v2.lane5 = extractelement <16 x i16> %v2.products, i32 5
  %v2.acc5 = add i16 %v2.acc4, %v2.lane5
  %v2.lane6 = extractelement <16 x i16> %v2.products, i32 6
  %v2.acc6 = add i16 %v2.acc5, %v2.lane6
  %v2.lane7 = extractelement <16 x i16> %v2.products, i32 7
  %v2.acc7 = add i16 %v2.acc6, %v2.lane7
  %v2.lane8 = extractelement <16 x i16> %v2.products, i32 8
  %v2.acc8 = add i16 %v2.acc7, %v2.lane8
  %v2.lane9 = extractelement <16 x i16> %v2.products, i32 9
  %v2.acc9 = add i16 %v2.acc8, %v2.lane9
  %v2.lane10 = extractelement <16 x i16> %v2.products, i32 10
  %v2.acc10 = add i16 %v2.acc9, %v2.lane10
  %v2.lane11 = extractelement <16 x i16> %v2.products, i32 11
  %v2.acc11 = add i16 %v2.acc10, %v2.lane11
  %v2.lane12 = extractelement <16 x i16> %v2.products, i32 12
  %v2.acc12 = add i16 %v2.acc11, %v2.lane12
  %v2.lane13 = extractelement <16 x i16> %v2.products, i32 13
  %v2.acc13 = add i16 %v2.acc12, %v2.lane13
  %v2.lane14 = extractelement <16 x i16> %v2.products, i32 14
  %v2.acc14 = add i16 %v2.acc13, %v2.lane14
  %v2.lane15 = extractelement <16 x i16> %v2.products, i32 15
  %v2 = add i16 %v2.acc14, %v2.lane15
  ret i16 %v2
}

define internal fastcc i32 @astra.fn.10(i32 %p0, <16 x i8> %p1, <16 x i8> %p2) {
b0:
  %v3.a = sext <16 x i8> %p1 to <16 x i32>
  %v3.b = sext <16 x i8> %p2 to <16 x i32>
  %v3.products = mul <16 x i32> %v3.a, %v3.b
  %v3.lane0 = extractelement <16 x i32> %v3.products, i32 0
  %v3.acc0 = add i32 %p0, %v3.lane0
  %v3.lane1 = extractelement <16 x i32> %v3.products, i32 1
  %v3.acc1 = add i32 %v3.acc0, %v3.lane1
  %v3.lane2 = extractelement <16 x i32> %v3.products, i32 2
  %v3.acc2 = add i32 %v3.acc1, %v3.lane2
  %v3.lane3 = extractelement <16 x i32> %v3.products, i32 3
  %v3.acc3 = add i32 %v3.acc2, %v3.lane3
  %v3.lane4 = extractelement <16 x i32> %v3.products, i32 4
  %v3.acc4 = add i32 %v3.acc3, %v3.lane4
  %v3.lane5 = extractelement <16 x i32> %v3.products, i32 5
  %v3.acc5 = add i32 %v3.acc4, %v3.lane5
  %v3.lane6 = extractelement <16 x i32> %v3.products, i32 6
  %v3.acc6 = add i32 %v3.acc5, %v3.lane6
  %v3.lane7 = extractelement <16 x i32> %v3.products, i32 7
  %v3.acc7 = add i32 %v3.acc6, %v3.lane7
  %v3.lane8 = extractelement <16 x i32> %v3.products, i32 8
  %v3.acc8 = add i32 %v3.acc7, %v3.lane8
  %v3.lane9 = extractelement <16 x i32> %v3.products, i32 9
  %v3.acc9 = add i32 %v3.acc8, %v3.lane9
  %v3.lane10 = extractelement <16 x i32> %v3.products, i32 10
  %v3.acc10 = add i32 %v3.acc9, %v3.lane10
  %v3.lane11 = extractelement <16 x i32> %v3.products, i32 11
  %v3.acc11 = add i32 %v3.acc10, %v3.lane11
  %v3.lane12 = extractelement <16 x i32> %v3.products, i32 12
  %v3.acc12 = add i32 %v3.acc11, %v3.lane12
  %v3.lane13 = extractelement <16 x i32> %v3.products, i32 13
  %v3.acc13 = add i32 %v3.acc12, %v3.lane13
  %v3.lane14 = extractelement <16 x i32> %v3.products, i32 14
  %v3.acc14 = add i32 %v3.acc13, %v3.lane14
  %v3.lane15 = extractelement <16 x i32> %v3.products, i32 15
  %v3 = add i32 %v3.acc14, %v3.lane15
  ret i32 %v3
}

define internal fastcc float @astra.fn.11(<4 x float> %p0, <4 x float> %p1) {
b0:
  %v2.products = fmul <4 x float> %p0, %p1
  %v2.lane0 = extractelement <4 x float> %v2.products, i32 0
  %v2.acc0 = fadd float 0.000000e+00, %v2.lane0
  %v2.lane1 = extractelement <4 x float> %v2.products, i32 1
  %v2.acc1 = fadd float %v2.acc0, %v2.lane1
  %v2.lane2 = extractelement <4 x float> %v2.products, i32 2
  %v2.acc2 = fadd float %v2.acc1, %v2.lane2
  %v2.lane3 = extractelement <4 x float> %v2.products, i32 3
  %v2 = fadd float %v2.acc2, %v2.lane3
  ret float %v2
}

define internal fastcc float @astra.fn.12(<2 x float> %p0, <2 x float> %p1) {
b0:
  %v2.products = fmul <2 x float> %p0, %p1
  %v2.lane0 = extractelement <2 x float> %v2.products, i32 0
  %v2.acc0 = fadd float 0.000000e+00, %v2.lane0
  %v2.lane1 = extractelement <2 x float> %v2.products, i32 1
  %v2 = fadd float %v2.acc0, %v2.lane1
  ret float %v2
}

define internal fastcc float @astra.fn.13(float %p0, <4 x float> %p1, <4 x float> %p2) {
b0:
  %v3.products = fmul <4 x float> %p1, %p2
  %v3.lane0 = extractelement <4 x float> %v3.products, i32 0
  %v3.acc0 = fadd float %p0, %v3.lane0
  %v3.lane1 = extractelement <4 x float> %v3.products, i32 1
  %v3.acc1 = fadd float %v3.acc0, %v3.lane1
  %v3.lane2 = extractelement <4 x float> %v3.products, i32 2
  %v3.acc2 = fadd float %v3.acc1, %v3.lane2
  %v3.lane3 = extractelement <4 x float> %v3.products, i32 3
  %v3 = fadd float %v3.acc2, %v3.lane3
  ret float %v3
}

define internal fastcc float @astra.fn.14(float %p0, <2 x float> %p1, <2 x float> %p2) {
b0:
  %v3.products = fmul <2 x float> %p1, %p2
  %v3.lane0 = extractelement <2 x float> %v3.products, i32 0
  %v3.acc0 = fadd float %p0, %v3.lane0
  %v3.lane1 = extractelement <2 x float> %v3.products, i32 1
  %v3 = fadd float %v3.acc0, %v3.lane1
  ret float %v3
}

define internal fastcc i32 @astra.fn.15() {
b0:
  ret i32 0
}
