; ModuleID = 'astra.scalar'
source_filename = "astra.scalar"

define internal fastcc i32 @astra.fn.0() {
b0:
  %v0 = call fastcc i32 @astra.fn.1(i32 1, i32 2)
  ret i32 %v0
}

define internal fastcc i32 @astra.fn.1(i32 %p0, i32 %p1) {
b0:
  %v2 = add i32 %p0, %p1
  ret i32 %v2
}

define internal fastcc i32 @astra.fn.2() {
b0:
  br label %b3

b1:                                               ; preds = %b5
  ret i32 1

b2:                                               ; preds = %b5
  ret i32 0

b3:                                               ; preds = %b0
  %v1 = call fastcc i32 @astra.fn.0()
  %v2 = icmp ne i32 %v1, 3
  br i1 %v2, label %b5, label %b4

b4:                                               ; preds = %b3
  %v3 = call i32 @c_call_astra_add(i32 20, i32 22)
  %v4 = icmp ne i32 %v3, 42
  br label %b5

b5:                                               ; preds = %b4, %b3
  %v0 = phi i1 [ true, %b3 ], [ %v4, %b4 ]
  br i1 %v0, label %b1, label %b2
}

declare i32 @c_call_astra_add(i32, i32)

define i32 @astra_export_add(i32 %0, i32 %1) {
entry:
  %result = call fastcc i32 @astra.fn.1(i32 %0, i32 %1)
  ret i32 %result
}
