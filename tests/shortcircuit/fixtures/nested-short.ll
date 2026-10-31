; ModuleID = 'astra.scalar'
source_filename = "astra.scalar"

define internal fastcc i1 @astra.fn.0(i1 %p0, i1 %p1, i1 %p2) {
b0:
  br label %b1

b1:                                               ; preds = %b0
  br label %b2

b2:                                               ; preds = %b1
  br i1 %p0, label %b3, label %b4

b3:                                               ; preds = %b2
  br label %b4

b4:                                               ; preds = %b3, %b2
  %v3 = phi i1 [ false, %b2 ], [ %p1, %b3 ]
  br i1 %v3, label %b5, label %b6

b5:                                               ; preds = %b4
  br label %b6

b6:                                               ; preds = %b5, %b4
  %v4 = phi i1 [ false, %b4 ], [ %p2, %b5 ]
  ret i1 %v4
}

define internal fastcc i1 @astra.fn.1(i1 %p0, i1 %p1, i1 %p2) {
b0:
  br label %b1

b1:                                               ; preds = %b0
  br label %b2

b2:                                               ; preds = %b1
  br i1 %p0, label %b4, label %b3

b3:                                               ; preds = %b2
  br label %b4

b4:                                               ; preds = %b3, %b2
  %v3 = phi i1 [ true, %b2 ], [ %p1, %b3 ]
  br i1 %v3, label %b6, label %b5

b5:                                               ; preds = %b4
  br label %b6

b6:                                               ; preds = %b5, %b4
  %v4 = phi i1 [ true, %b4 ], [ %p2, %b5 ]
  ret i1 %v4
}

define internal fastcc i1 @astra.fn.2(i1 %p0, i1 %p1, i1 %p2) {
b0:
  br label %b1

b1:                                               ; preds = %b0
  br i1 %p0, label %b2, label %b3

b2:                                               ; preds = %b1
  br label %b4

b3:                                               ; preds = %b6, %b1
  %v3 = phi i1 [ false, %b1 ], [ %v4, %b6 ]
  ret i1 %v3

b4:                                               ; preds = %b2
  br i1 %p1, label %b6, label %b5

b5:                                               ; preds = %b4
  br label %b6

b6:                                               ; preds = %b5, %b4
  %v4 = phi i1 [ true, %b4 ], [ %p2, %b5 ]
  br label %b3
}

define internal fastcc i1 @astra.fn.3(i1 %p0, i1 %p1, i1 %p2) {
b0:
  br label %b1

b1:                                               ; preds = %b0
  br i1 %p0, label %b3, label %b2

b2:                                               ; preds = %b1
  br label %b4

b3:                                               ; preds = %b6, %b1
  %v3 = phi i1 [ true, %b1 ], [ %v4, %b6 ]
  ret i1 %v3

b4:                                               ; preds = %b2
  br i1 %p1, label %b5, label %b6

b5:                                               ; preds = %b4
  br label %b6

b6:                                               ; preds = %b5, %b4
  %v4 = phi i1 [ false, %b4 ], [ %p2, %b5 ]
  br label %b3
}

define internal fastcc i1 @astra.fn.4(i1 %p0, i1 %p1, i1 %p2, i1 %p3, i1 %p4) {
b0:
  br label %b1

b1:                                               ; preds = %b0
  br label %b2

b2:                                               ; preds = %b1
  %v7 = icmp eq i1 %p0, %p1
  br i1 %v7, label %b3, label %b4

b3:                                               ; preds = %b2
  %v8 = icmp ne i1 %p2, %p3
  br label %b4

b4:                                               ; preds = %b3, %b2
  %v5 = phi i1 [ false, %b2 ], [ %v8, %b3 ]
  br i1 %v5, label %b6, label %b5

b5:                                               ; preds = %b4
  br label %b6

b6:                                               ; preds = %b5, %b4
  %v6 = phi i1 [ true, %b4 ], [ %p4, %b5 ]
  ret i1 %v6
}
