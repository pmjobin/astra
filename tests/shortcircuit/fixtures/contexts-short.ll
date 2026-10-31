; ModuleID = 'astra.scalar'
source_filename = "astra.scalar"

define internal fastcc i1 @astra.fn.0(i1 %p0, i1 %p1) {
b0:
  %v2 = icmp eq i1 %p0, %p1
  ret i1 %v2
}

define internal fastcc i1 @astra.fn.1(i1 %p0, i1 %p1, i1 %p2) {
b0:
  br label %b1

b1:                                               ; preds = %b0
  br i1 %p0, label %b2, label %b3

b2:                                               ; preds = %b1
  br label %b3

b3:                                               ; preds = %b2, %b1
  %v3 = phi i1 [ false, %b1 ], [ %p1, %b2 ]
  br label %b4

b4:                                               ; preds = %b3
  br i1 %v3, label %b6, label %b5

b5:                                               ; preds = %b4
  br label %b6

b6:                                               ; preds = %b5, %b4
  %v4 = phi i1 [ true, %b4 ], [ %p2, %b5 ]
  br label %b9

b7:                                               ; preds = %b11
  br label %b12

b8:                                               ; preds = %b14, %b11
  %v5 = phi i1 [ %v4, %b11 ], [ %v7, %b14 ]
  br label %b15

b9:                                               ; preds = %b6
  br i1 %p0, label %b10, label %b11

b10:                                              ; preds = %b9
  br label %b11

b11:                                              ; preds = %b10, %b9
  %v6 = phi i1 [ false, %b9 ], [ %p2, %b10 ]
  br i1 %v6, label %b7, label %b8

b12:                                              ; preds = %b7
  br i1 %p1, label %b14, label %b13

b13:                                              ; preds = %b12
  br label %b14

b14:                                              ; preds = %b13, %b12
  %v7 = phi i1 [ true, %b12 ], [ %p2, %b13 ]
  br label %b8

b15:                                              ; preds = %b8
  br i1 %v5, label %b16, label %b17

b16:                                              ; preds = %b15
  br label %b17

b17:                                              ; preds = %b16, %b15
  %v8 = phi i1 [ false, %b15 ], [ %p1, %b16 ]
  br label %b18

b18:                                              ; preds = %b17
  br i1 %p0, label %b20, label %b19

b19:                                              ; preds = %b18
  br label %b20

b20:                                              ; preds = %b19, %b18
  %v9 = phi i1 [ true, %b18 ], [ %p2, %b19 ]
  %v13 = call fastcc i1 @astra.fn.0(i1 %v8, i1 %v9)
  br label %b21

b21:                                              ; preds = %b20
  br i1 %v5, label %b22, label %b23

b22:                                              ; preds = %b21
  br label %b24

b23:                                              ; preds = %b26, %b21
  %v10 = phi i1 [ false, %b21 ], [ %v11, %b26 ]
  br label %b27

b24:                                              ; preds = %b22
  br i1 %p0, label %b26, label %b25

b25:                                              ; preds = %b24
  br label %b26

b26:                                              ; preds = %b25, %b24
  %v11 = phi i1 [ true, %b24 ], [ %p1, %b25 ]
  br label %b23

b27:                                              ; preds = %b23
  br i1 %p1, label %b29, label %b28

b28:                                              ; preds = %b27
  br label %b29

b29:                                              ; preds = %b28, %b27
  %v12 = phi i1 [ true, %b27 ], [ %p2, %b28 ]
  %v14 = xor i1 %v10, true
  %v15 = icmp eq i1 %v14, %v12
  ret i1 %v15
}
