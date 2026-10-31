; ModuleID = 'astra.scalar'
source_filename = "astra.scalar"

define internal fastcc i32 @astra.fn.0() {
b0:
  %v0 = call i32 @astra_test_add(i32 20, i32 22)
  %v1 = icmp ne i32 %v0, 42
  br i1 %v1, label %b1, label %b2

b1:                                               ; preds = %b0
  ret i32 1

b2:                                               ; preds = %b0
  %v2 = call i32 @astra_test_identity(i32 -2147483648)
  %v3 = icmp ne i32 %v2, -2147483648
  br i1 %v3, label %b3, label %b4

b3:                                               ; preds = %b2
  ret i32 2

b4:                                               ; preds = %b2
  %v4 = call i32 @astra_test_identity(i32 2147483647)
  %v5 = icmp ne i32 %v4, 2147483647
  br i1 %v5, label %b5, label %b6

b5:                                               ; preds = %b4
  ret i32 3

b6:                                               ; preds = %b4
  ret i32 0
}

declare i32 @astra_test_add(i32, i32)

declare i32 @astra_test_identity(i32)
