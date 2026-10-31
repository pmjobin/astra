; ModuleID = 'astra.scalar'
source_filename = "astra.scalar"

define internal fastcc i32 @astra.fn.0() {
b0:
  br label %b3

b1:                                               ; preds = %b14
  ret i32 42

b2:                                               ; preds = %b14
  ret i32 1

b3:                                               ; preds = %b0
  br label %b4

b4:                                               ; preds = %b3
  br label %b5

b5:                                               ; preds = %b4
  br label %b6

b6:                                               ; preds = %b5
  %v4 = call fastcc i32 @astra.fn.1(i32 2147483647, i32 1)
  %v5 = icmp eq i32 %v4, -2147483648
  br i1 %v5, label %b7, label %b8

b7:                                               ; preds = %b6
  %v6 = call fastcc i32 @astra.fn.2(i32 84, i32 2)
  %v7 = icmp eq i32 %v6, 42
  br label %b8

b8:                                               ; preds = %b7, %b6
  %v0 = phi i1 [ false, %b6 ], [ %v7, %b7 ]
  br i1 %v0, label %b9, label %b10

b9:                                               ; preds = %b8
  %v8 = call fastcc double @astra.fn.3(double 8.400000e+01, double 2.000000e+00)
  %v9 = fcmp oeq double %v8, 4.200000e+01
  br label %b10

b10:                                              ; preds = %b9, %b8
  %v1 = phi i1 [ false, %b8 ], [ %v9, %b9 ]
  br i1 %v1, label %b11, label %b12

b11:                                              ; preds = %b10
  %v10 = call fastcc double @astra.fn.4(i32 3, double 1.000000e+00, double 2.000000e+00)
  %v11 = fcmp oeq double %v10, 7.000000e+00
  br label %b12

b12:                                              ; preds = %b11, %b10
  %v2 = phi i1 [ false, %b10 ], [ %v11, %b11 ]
  br i1 %v2, label %b13, label %b14

b13:                                              ; preds = %b12
  %v12 = call fastcc double @astra.fn.5(double 0x3FF0000000000001, double 0x3FEFFFFFFFFFFFFE, double -1.000000e+00)
  %v13 = fcmp oeq double %v12, 0.000000e+00
  br label %b14

b14:                                              ; preds = %b13, %b12
  %v3 = phi i1 [ false, %b12 ], [ %v13, %b13 ]
  br i1 %v3, label %b1, label %b2
}

define internal fastcc i32 @astra.fn.1(i32 %p0, i32 %p1) {
b0:
  %v2 = add i32 %p0, %p1
  ret i32 %v2
}

define internal fastcc i32 @astra.fn.2(i32 %p0, i32 %p1) {
b0:
  %v2.zero = icmp eq i32 %p1, 0
  br i1 %v2.zero, label %v2.trap, label %v2.nonzero

v2.trap:                                          ; preds = %b0
  call void @llvm.trap()
  unreachable

v2.nonzero:                                       ; preds = %b0
  %v2.minimum = icmp eq i32 %p0, -2147483648
  %v2.minusone = icmp eq i32 %p1, -1
  %v2.overflow = and i1 %v2.minimum, %v2.minusone
  br i1 %v2.overflow, label %v2.special, label %v2.normal

v2.special:                                       ; preds = %v2.nonzero
  br label %v2.continue

v2.normal:                                        ; preds = %v2.nonzero
  %v2.raw = sdiv i32 %p0, %p1
  br label %v2.continue

v2.continue:                                      ; preds = %v2.normal, %v2.special
  %v2 = phi i32 [ -2147483648, %v2.special ], [ %v2.raw, %v2.normal ]
  ret i32 %v2
}

define internal fastcc double @astra.fn.3(double %p0, double %p1) {
b0:
  %v2 = fdiv double %p0, %p1
  ret double %v2
}

define internal fastcc double @astra.fn.4(i32 %p0, double %p1, double %p2) {
b0:
  br label %b1

b1:                                               ; preds = %b2, %b0
  %v3 = phi double [ %p1, %b0 ], [ %v6, %b2 ]
  %v4 = phi i32 [ %p0, %b0 ], [ %v7, %b2 ]
  %v5 = icmp sgt i32 %v4, 0
  br i1 %v5, label %b2, label %b3

b2:                                               ; preds = %b1
  %v6 = fadd double %v3, %p2
  %v7 = sub i32 %v4, 1
  br label %b1

b3:                                               ; preds = %b1
  ret double %v3
}

define internal fastcc double @astra.fn.5(double %p0, double %p1, double %p2) {
b0:
  %v3 = fmul double %p0, %p1
  %v4 = fadd double %v3, %p2
  ret double %v4
}

; Function Attrs: cold noreturn nounwind memory(inaccessiblemem: write)
declare void @llvm.trap() #0

attributes #0 = { cold noreturn nounwind memory(inaccessiblemem: write) }
