; ModuleID = 'astra.scalar'
source_filename = "astra.scalar"

define internal fastcc i32 @astra.fn.0() {
b0:
  br label %b3

b1:                                               ; preds = %b8
  ret i32 1

b2:                                               ; preds = %b8
  br label %b11

b3:                                               ; preds = %b0
  br label %b4

b4:                                               ; preds = %b3
  br i1 false, label %b6, label %b5

b5:                                               ; preds = %b4
  br label %b6

b6:                                               ; preds = %b5, %b4
  %v0 = phi i1 [ true, %b4 ], [ false, %b5 ]
  br i1 %v0, label %b8, label %b7

b7:                                               ; preds = %b6
  br label %b8

b8:                                               ; preds = %b7, %b6
  %v1 = phi i1 [ true, %b6 ], [ false, %b7 ]
  br i1 %v1, label %b1, label %b2

b9:                                               ; preds = %b13
  ret i32 2

b10:                                              ; preds = %b13
  ret i32 0

b11:                                              ; preds = %b2
  br i1 false, label %b13, label %b12

b12:                                              ; preds = %b11
  br label %b13

b13:                                              ; preds = %b12, %b11
  %v2 = phi i1 [ true, %b11 ], [ false, %b12 ]
  br i1 %v2, label %b9, label %b10
}
