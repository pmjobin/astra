; ModuleID = 'astra.scalar'
source_filename = "astra.scalar"

define internal fastcc i8 @astra.fn.0(i8 %p0) {
b0:
  ret i8 %p0
}

define internal fastcc i32 @astra.fn.1() {
b0:
  ret i32 -294967296
}

define internal fastcc i8 @astra.fn.2() {
b0:
  ret i8 -128
}

define internal fastcc i16 @astra.fn.3() {
b0:
  ret i16 -32768
}

define internal fastcc i32 @astra.fn.4() {
b0:
  %v16 = call fastcc i8 @astra.fn.0(i8 -1)
  br label %b3

b1:                                               ; preds = %b11
  ret i32 1

b2:                                               ; preds = %b11
  br label %b14

b3:                                               ; preds = %b0
  br label %b4

b4:                                               ; preds = %b3
  br label %b5

b5:                                               ; preds = %b4
  br i1 false, label %b7, label %b6

b6:                                               ; preds = %b5
  br label %b7

b7:                                               ; preds = %b6, %b5
  %v0 = phi i1 [ true, %b5 ], [ false, %b6 ]
  br i1 %v0, label %b9, label %b8

b8:                                               ; preds = %b7
  %v19 = call fastcc i32 @astra.fn.1()
  %v20 = icmp ne i32 -294967296, %v19
  br label %b9

b9:                                               ; preds = %b8, %b7
  %v1 = phi i1 [ true, %b7 ], [ %v20, %b8 ]
  br i1 %v1, label %b11, label %b10

b10:                                              ; preds = %b9
  %v21 = call fastcc i16 @astra.fn.3()
  %v22 = icmp ne i16 -32768, %v21
  br label %b11

b11:                                              ; preds = %b10, %b9
  %v2 = phi i1 [ true, %b9 ], [ %v22, %b10 ]
  br i1 %v2, label %b1, label %b2

b12:                                              ; preds = %b22
  ret i32 2

b13:                                              ; preds = %b22
  br label %b25

b14:                                              ; preds = %b2
  br label %b15

b15:                                              ; preds = %b14
  br label %b16

b16:                                              ; preds = %b15
  %v23 = icmp ne i8 %v16, -1
  br i1 %v23, label %b18, label %b17

b17:                                              ; preds = %b16
  br label %b18

b18:                                              ; preds = %b17, %b16
  %v3 = phi i1 [ true, %b16 ], [ false, %b17 ]
  br i1 %v3, label %b20, label %b19

b19:                                              ; preds = %b18
  br label %b20

b20:                                              ; preds = %b19, %b18
  %v4 = phi i1 [ true, %b18 ], [ false, %b19 ]
  br i1 %v4, label %b22, label %b21

b21:                                              ; preds = %b20
  br label %b22

b22:                                              ; preds = %b21, %b20
  %v5 = phi i1 [ true, %b20 ], [ false, %b21 ]
  br i1 %v5, label %b12, label %b13

b23:                                              ; preds = %b33
  ret i32 3

b24:                                              ; preds = %b33
  br label %b36

b25:                                              ; preds = %b13
  br label %b26

b26:                                              ; preds = %b25
  br label %b27

b27:                                              ; preds = %b26
  %v27 = add i8 1, %v16
  %v28 = icmp ne i8 %v27, 0
  br i1 %v28, label %b29, label %b28

b28:                                              ; preds = %b27
  %v29 = add i8 %v16, 1
  %v30 = icmp ne i8 %v29, 0
  br label %b29

b29:                                              ; preds = %b28, %b27
  %v6 = phi i1 [ true, %b27 ], [ %v30, %b28 ]
  br i1 %v6, label %b31, label %b30

b30:                                              ; preds = %b29
  %v31 = add i8 1, %v16
  %v32 = icmp ne i8 0, %v31
  br label %b31

b31:                                              ; preds = %b30, %b29
  %v7 = phi i1 [ true, %b29 ], [ %v32, %b30 ]
  br i1 %v7, label %b33, label %b32

b32:                                              ; preds = %b31
  %v33 = call fastcc i8 @astra.fn.2()
  %v34 = icmp ne i8 %v33, -128
  br label %b33

b33:                                              ; preds = %b32, %b31
  %v8 = phi i1 [ true, %b31 ], [ %v34, %b32 ]
  br i1 %v8, label %b23, label %b24

b34:                                              ; preds = %b41
  ret i32 4

b35:                                              ; preds = %b41
  ret i32 0

b36:                                              ; preds = %b24
  br label %b37

b37:                                              ; preds = %b36
  %v35 = add i8 2, %v16
  %v36 = add i8 1, %v35
  %v37 = icmp ne i8 %v36, 2
  br i1 %v37, label %b39, label %b38

b38:                                              ; preds = %b37
  %v38 = call fastcc i8 @astra.fn.0(i8 -1)
  %v39 = add i8 2, %v38
  %v40 = add i8 1, %v39
  %v41 = icmp ne i8 %v40, 2
  br label %b39

b39:                                              ; preds = %b38, %b37
  %v9 = phi i1 [ true, %b37 ], [ %v41, %b38 ]
  br i1 %v9, label %b41, label %b40

b40:                                              ; preds = %b39
  br label %b41

b41:                                              ; preds = %b40, %b39
  %v10 = phi i1 [ true, %b39 ], [ false, %b40 ]
  br i1 %v10, label %b34, label %b35
}
