; ModuleID = 'astra.scalar'
source_filename = "astra.scalar"

define internal fastcc i1 @astra.fn.0(ptr %p0) {
b0:
  %v1 = icmp eq ptr %p0, null
  ret i1 %v1
}

define internal fastcc i1 @astra.fn.1(ptr %p0) {
b0:
  %v1 = icmp ne ptr %p0, null
  ret i1 %v1
}

define internal fastcc ptr @astra.fn.2(i1 %p0) {
b0:
  br i1 %p0, label %b1, label %b2

b1:                                               ; preds = %b0
  %v2 = call ptr @astra_test_resource_raw()
  br label %b2

b2:                                               ; preds = %b1, %b0
  %v1 = phi ptr [ null, %b0 ], [ %v2, %b1 ]
  ret ptr %v1
}

define internal fastcc i32 @astra.fn.3() {
b0:
  %v0 = call ptr @astra_test_resource_create(i32 1)
  %v1 = call i32 @astra_test_resource_id(ptr %v0)
  %v2 = call ptr @astra_test_resource_create_same(i32 0)
  %v3 = call fastcc i1 @astra.fn.1(ptr %v2)
  br i1 %v3, label %b1, label %b2

b1:                                               ; preds = %b0
  %cleanup0.null = icmp eq ptr %v0, null
  br i1 %cleanup0.null, label %cleanup0.continue, label %cleanup0.call

b2:                                               ; preds = %b0
  %cleanup2.null = icmp eq ptr %v2, null
  br i1 %cleanup2.null, label %cleanup2.continue, label %cleanup2.call

cleanup0.call:                                    ; preds = %b1
  call void @astra_test_resource_destroy(ptr %v0)
  br label %cleanup0.continue

cleanup0.continue:                                ; preds = %cleanup0.call, %b1
  %cleanup1.null = icmp eq ptr %v2, null
  br i1 %cleanup1.null, label %cleanup1.continue, label %cleanup1.call

cleanup1.call:                                    ; preds = %cleanup0.continue
  call void @astra_test_resource_destroy(ptr %v2)
  br label %cleanup1.continue

cleanup1.continue:                                ; preds = %cleanup1.call, %cleanup0.continue
  ret i32 1

cleanup2.call:                                    ; preds = %b2
  call void @astra_test_resource_destroy(ptr %v2)
  br label %cleanup2.continue

cleanup2.continue:                                ; preds = %cleanup2.call, %b2
  %v4 = call ptr @astra_test_resource_create(i32 2)
  %v5 = call i32 @astra_test_resource_id(ptr %v4)
  %v6 = call i32 @astra_test_resource_id(ptr %v0)
  %cleanup3.null = icmp eq ptr %v0, null
  br i1 %cleanup3.null, label %cleanup3.continue, label %cleanup3.call

cleanup3.call:                                    ; preds = %cleanup2.continue
  call void @astra_test_resource_destroy(ptr %v0)
  br label %cleanup3.continue

cleanup3.continue:                                ; preds = %cleanup3.call, %cleanup2.continue
  %cleanup4.null = icmp eq ptr %v4, null
  br i1 %cleanup4.null, label %cleanup4.continue, label %cleanup4.call

cleanup4.call:                                    ; preds = %cleanup3.continue
  call void @astra_test_resource_destroy(ptr %v4)
  br label %cleanup4.continue

cleanup4.continue:                                ; preds = %cleanup4.call, %cleanup3.continue
  ret i32 %v6
}

declare void @astra_test_resource_destroy(ptr)

declare ptr @astra_test_resource_create(i32)

declare ptr @astra_test_resource_create_same(i32)

declare i32 @astra_test_resource_id(ptr)

declare i32 @astra_test_resource_touch(ptr)

declare ptr @astra_test_resource_raw()

declare void @astra_test_resource_raw_destroy(ptr)

declare void @astra_test_resource_reset()

declare i32 @astra_test_resource_live_count()

declare i32 @astra_test_resource_create_count()

declare i32 @astra_test_resource_destroy_count()

declare i32 @astra_test_resource_destroy_order()

declare i32 @astra_test_resource_error_count()

declare i32 @astra_test_resource_effect_order()

declare i32 @astra_test_resource_is_live(ptr)

declare i32 @astra_test_resource_touch_count()

declare i32 @astra_test_resource_null_count()

declare i32 @astra_test_resource_observe3(i32, ptr, i32)
