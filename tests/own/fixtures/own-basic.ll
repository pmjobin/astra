; ModuleID = 'astra.scalar'
source_filename = "astra.scalar"

define internal fastcc i32 @astra.fn.0() {
b0:
  %v0 = call ptr @astra_test_resource_create(i32 1)
  %cleanup0.null = icmp eq ptr %v0, null
  br i1 %cleanup0.null, label %cleanup0.continue, label %cleanup0.call

cleanup0.call:                                    ; preds = %b0
  call void @astra_test_resource_destroy(ptr %v0)
  br label %cleanup0.continue

cleanup0.continue:                                ; preds = %cleanup0.call, %b0
  ret i32 7
}

define internal fastcc i32 @astra.fn.1() {
b0:
  call void @astra_test_resource_reset()
  %v0 = call fastcc i32 @astra.fn.0()
  %v1 = icmp ne i32 %v0, 7
  br i1 %v1, label %b1, label %b2

b1:                                               ; preds = %b0
  ret i32 1

b2:                                               ; preds = %b0
  %v2 = call i32 @astra_test_resource_live_count()
  %v3 = icmp ne i32 %v2, 0
  br i1 %v3, label %b3, label %b4

b3:                                               ; preds = %b2
  ret i32 2

b4:                                               ; preds = %b2
  %v4 = call i32 @astra_test_resource_destroy_count()
  %v5 = icmp ne i32 %v4, 1
  br i1 %v5, label %b5, label %b6

b5:                                               ; preds = %b4
  ret i32 3

b6:                                               ; preds = %b4
  %v6 = call i32 @astra_test_resource_destroy_order()
  %v7 = icmp ne i32 %v6, 1
  br i1 %v7, label %b7, label %b8

b7:                                               ; preds = %b6
  ret i32 4

b8:                                               ; preds = %b6
  %v8 = call i32 @astra_test_resource_error_count()
  %v9 = icmp ne i32 %v8, 0
  br i1 %v9, label %b9, label %b10

b9:                                               ; preds = %b8
  ret i32 5

b10:                                              ; preds = %b8
  ret i32 0
}

declare void @astra_test_resource_destroy(ptr)

declare ptr @astra_test_resource_create(i32)

declare void @astra_test_resource_reset()

declare i32 @astra_test_resource_live_count()

declare i32 @astra_test_resource_create_count()

declare i32 @astra_test_resource_destroy_count()

declare i32 @astra_test_resource_destroy_order()

declare i32 @astra_test_resource_error_count()

declare i32 @astra_test_resource_record_effect(i32)

declare i32 @astra_test_resource_effect_order()

declare void @astra_test_resource_forbid_cleanup()
