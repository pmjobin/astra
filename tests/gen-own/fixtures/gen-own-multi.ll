; ModuleID = 'astra.scalar'
source_filename = "astra.scalar"

%astra.class.0 = type { i32 }

define internal fastcc i32 @astra.fn.0() {
b0:
  %object0 = alloca %astra.class.0, align 8
  %object1 = alloca %astra.class.0, align 8
  call fastcc void @astra.ctor.0(ptr %object0, i32 65)
  %v5 = call fastcc i32 @astra.fn.3(ptr %object0, i32 42)
  %v6 = call i32 @life_record(i32 83, i32 0)
  %v7 = call ptr @life_create(i32 66)
  %v8 = call fastcc double @astra.fn.4(ptr %v7, double -0.000000e+00)
  %v9 = call i32 @life_record(i32 83, i32 0)
  call fastcc void @astra.ctor.0(ptr %object1, i32 67)
  %v13 = call fastcc <8 x i16> @astra.fn.5(ptr %object1, <8 x i16> <i16 1, i16 2, i16 3, i16 4, i16 5, i16 6, i16 7, i16 8>)
  %v14 = call i32 @life_record(i32 83, i32 0)
  %v15 = call ptr @life_create(i32 68)
  %v16 = call fastcc double @astra.fn.6(ptr %v15, double 0x3FF0000002000000, double 0x3FEFFFFFFC000000, double -1.000000e+00)
  %v17 = call i32 @life_record(i32 83, i32 0)
  br label %b3

b1:                                               ; preds = %b11
  br i1 true, label %cleanup0.continue, label %cleanup0.call

b2:                                               ; preds = %b11
  br i1 true, label %cleanup4.continue, label %cleanup4.call

b3:                                               ; preds = %b0
  br label %b4

b4:                                               ; preds = %b3
  br label %b5

b5:                                               ; preds = %b4
  %v18 = icmp ne i32 %v5, 42
  br i1 %v18, label %b7, label %b6

b6:                                               ; preds = %b5
  %v19 = fcmp une double %v8, 0.000000e+00
  br label %b7

b7:                                               ; preds = %b6, %b5
  %v0 = phi i1 [ true, %b5 ], [ %v19, %b6 ]
  br i1 %v0, label %b9, label %b8

b8:                                               ; preds = %b7
  %v20 = fcmp une double %v16, 0.000000e+00
  br label %b9

b9:                                               ; preds = %b8, %b7
  %v1 = phi i1 [ true, %b7 ], [ %v20, %b8 ]
  br i1 %v1, label %b11, label %b10

b10:                                              ; preds = %b9
  %v21 = icmp eq <8 x i16> %v13, <i16 1, i16 2, i16 3, i16 4, i16 5, i16 6, i16 7, i16 8>
  %v22.lane0 = extractelement <8 x i1> %v21, i32 0
  %v22.lane1 = extractelement <8 x i1> %v21, i32 1
  %v22.reduce1 = and i1 %v22.lane0, %v22.lane1
  %v22.lane2 = extractelement <8 x i1> %v21, i32 2
  %v22.reduce2 = and i1 %v22.reduce1, %v22.lane2
  %v22.lane3 = extractelement <8 x i1> %v21, i32 3
  %v22.reduce3 = and i1 %v22.reduce2, %v22.lane3
  %v22.lane4 = extractelement <8 x i1> %v21, i32 4
  %v22.reduce4 = and i1 %v22.reduce3, %v22.lane4
  %v22.lane5 = extractelement <8 x i1> %v21, i32 5
  %v22.reduce5 = and i1 %v22.reduce4, %v22.lane5
  %v22.lane6 = extractelement <8 x i1> %v21, i32 6
  %v22.reduce6 = and i1 %v22.reduce5, %v22.lane6
  %v22.lane7 = extractelement <8 x i1> %v21, i32 7
  %v22 = and i1 %v22.reduce6, %v22.lane7
  %v23 = xor i1 %v22, true
  br label %b11

b11:                                              ; preds = %b10, %b9
  %v2 = phi i1 [ true, %b9 ], [ %v23, %b10 ]
  br i1 %v2, label %b1, label %b2

cleanup0.call:                                    ; preds = %b1
  call void @life_destroy(ptr null)
  br label %cleanup0.continue

cleanup0.continue:                                ; preds = %cleanup0.call, %b1
  br i1 true, label %cleanup1.continue, label %cleanup1.call

cleanup1.call:                                    ; preds = %cleanup0.continue
  call fastcc void @astra.dtor.0(ptr null)
  br label %cleanup1.continue

cleanup1.continue:                                ; preds = %cleanup1.call, %cleanup0.continue
  br i1 true, label %cleanup2.continue, label %cleanup2.call

cleanup2.call:                                    ; preds = %cleanup1.continue
  call void @life_destroy(ptr null)
  br label %cleanup2.continue

cleanup2.continue:                                ; preds = %cleanup2.call, %cleanup1.continue
  br i1 true, label %cleanup3.continue, label %cleanup3.call

cleanup3.call:                                    ; preds = %cleanup2.continue
  call fastcc void @astra.dtor.0(ptr null)
  br label %cleanup3.continue

cleanup3.continue:                                ; preds = %cleanup3.call, %cleanup2.continue
  ret i32 1

cleanup4.call:                                    ; preds = %b2
  call void @life_destroy(ptr null)
  br label %cleanup4.continue

cleanup4.continue:                                ; preds = %cleanup4.call, %b2
  br i1 true, label %cleanup5.continue, label %cleanup5.call

cleanup5.call:                                    ; preds = %cleanup4.continue
  call fastcc void @astra.dtor.0(ptr null)
  br label %cleanup5.continue

cleanup5.continue:                                ; preds = %cleanup5.call, %cleanup4.continue
  br i1 true, label %cleanup6.continue, label %cleanup6.call

cleanup6.call:                                    ; preds = %cleanup5.continue
  call void @life_destroy(ptr null)
  br label %cleanup6.continue

cleanup6.continue:                                ; preds = %cleanup6.call, %cleanup5.continue
  br i1 true, label %cleanup7.continue, label %cleanup7.call

cleanup7.call:                                    ; preds = %cleanup6.continue
  call fastcc void @astra.dtor.0(ptr null)
  br label %cleanup7.continue

cleanup7.continue:                                ; preds = %cleanup7.call, %cleanup6.continue
  ret i32 42
}

define internal fastcc void @astra.ctor.0(ptr %this, i32 %p0) {
b0:
  %memory0.field = getelementptr inbounds nuw %astra.class.0, ptr %this, i32 0, i32 0
  store i32 %p0, ptr %memory0.field, align 4
  ret void
}

define internal fastcc void @astra.dtor.0(ptr %this) {
b0:
  %memory0.field = getelementptr inbounds nuw %astra.class.0, ptr %this, i32 0, i32 0
  %v1 = load i32, ptr %memory0.field, align 4
  %v2 = call i32 @life_record(i32 %v1, i32 0)
  ret void
}

define internal fastcc i32 @astra.fn.3(ptr %p0, i32 %p1) {
b0:
  %v2 = call fastcc i32 @astra.fn.7(i32 %p1)
  %cleanup0.null = icmp eq ptr %p0, null
  br i1 %cleanup0.null, label %cleanup0.continue, label %cleanup0.call

cleanup0.call:                                    ; preds = %b0
  call fastcc void @astra.dtor.0(ptr %p0)
  br label %cleanup0.continue

cleanup0.continue:                                ; preds = %cleanup0.call, %b0
  ret i32 %v2
}

define internal fastcc double @astra.fn.4(ptr %p0, double %p1) {
b0:
  %v2 = call fastcc double @astra.fn.8(double %p1)
  %cleanup0.null = icmp eq ptr %p0, null
  br i1 %cleanup0.null, label %cleanup0.continue, label %cleanup0.call

cleanup0.call:                                    ; preds = %b0
  call void @life_destroy(ptr %p0)
  br label %cleanup0.continue

cleanup0.continue:                                ; preds = %cleanup0.call, %b0
  ret double %v2
}

define internal fastcc <8 x i16> @astra.fn.5(ptr %p0, <8 x i16> %p1) {
b0:
  %v2 = call fastcc <8 x i16> @astra.fn.9(<8 x i16> %p1)
  %cleanup0.null = icmp eq ptr %p0, null
  br i1 %cleanup0.null, label %cleanup0.continue, label %cleanup0.call

cleanup0.call:                                    ; preds = %b0
  call fastcc void @astra.dtor.0(ptr %p0)
  br label %cleanup0.continue

cleanup0.continue:                                ; preds = %cleanup0.call, %b0
  ret <8 x i16> %v2
}

define internal fastcc double @astra.fn.6(ptr %p0, double %p1, double %p2, double %p3) {
b0:
  %v4 = fmul double %p1, %p2
  %v5 = fadd double %v4, %p3
  %v6 = call fastcc double @astra.fn.8(double %v5)
  %cleanup0.null = icmp eq ptr %p0, null
  br i1 %cleanup0.null, label %cleanup0.continue, label %cleanup0.call

cleanup0.call:                                    ; preds = %b0
  call void @life_destroy(ptr %p0)
  br label %cleanup0.continue

cleanup0.continue:                                ; preds = %cleanup0.call, %b0
  ret double %v6
}

define internal fastcc i32 @astra.fn.7(i32 %p0) {
b0:
  %v1 = call i32 @life_record(i32 86, i32 0)
  ret i32 %p0
}

define internal fastcc double @astra.fn.8(double %p0) {
b0:
  %v1 = call i32 @life_record(i32 86, i32 0)
  ret double %p0
}

define internal fastcc <8 x i16> @astra.fn.9(<8 x i16> %p0) {
b0:
  %v1 = call i32 @life_record(i32 86, i32 0)
  ret <8 x i16> %p0
}

declare void @life_destroy(ptr)

declare i32 @life_record(i32, i32)

declare ptr @life_create(i32)

declare ptr @own_token_create(i32)

declare i32 @life_id(ptr)
