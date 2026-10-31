; ModuleID = 'astra.scalar'
source_filename = "astra.scalar"

define internal fastcc ptr @astra.fn.0(ptr %p0) {
b0:
  br i1 true, label %cleanup0.continue, label %cleanup0.call

cleanup0.call:                                    ; preds = %b0
  call void @astra_test_resource_destroy(ptr null)
  br label %cleanup0.continue

cleanup0.continue:                                ; preds = %cleanup0.call, %b0
  ret ptr %p0
}

define internal fastcc void @astra.fn.1(i32 %p0, ptr %p1, i32 %p2, ptr %p3) {
b0:
  %v4 = call ptr @astra_test_resource_create(i32 3)
  %cleanup0.null = icmp eq ptr %v4, null
  br i1 %cleanup0.null, label %cleanup0.continue, label %cleanup0.call

cleanup0.call:                                    ; preds = %b0
  call void @astra_test_resource_destroy(ptr %v4)
  br label %cleanup0.continue

cleanup0.continue:                                ; preds = %cleanup0.call, %b0
  %cleanup1.null = icmp eq ptr %p3, null
  br i1 %cleanup1.null, label %cleanup1.continue, label %cleanup1.call

cleanup1.call:                                    ; preds = %cleanup0.continue
  call void @astra_test_resource_destroy(ptr %p3)
  br label %cleanup1.continue

cleanup1.continue:                                ; preds = %cleanup1.call, %cleanup0.continue
  %cleanup2.null = icmp eq ptr %p1, null
  br i1 %cleanup2.null, label %cleanup2.continue, label %cleanup2.call

cleanup2.call:                                    ; preds = %cleanup1.continue
  call void @astra_test_resource_destroy(ptr %p1)
  br label %cleanup2.continue

cleanup2.continue:                                ; preds = %cleanup2.call, %cleanup1.continue
  ret void
}

define internal fastcc i32 @astra.fn.2() {
b0:
  %v0 = call ptr @astra_test_resource_create(i32 1)
  %v1 = call fastcc ptr @astra.fn.0(ptr %v0)
  %v2 = call fastcc ptr @astra.fn.0(ptr null)
  %v3 = call i32 @astra_test_resource_record_effect(i32 1)
  %v4 = call i32 @astra_test_resource_record_effect(i32 2)
  call fastcc void @astra.fn.1(i32 %v3, ptr %v1, i32 %v4, ptr %v2)
  br i1 true, label %cleanup0.continue, label %cleanup0.call

cleanup0.call:                                    ; preds = %b0
  call void @astra_test_resource_destroy(ptr null)
  br label %cleanup0.continue

cleanup0.continue:                                ; preds = %cleanup0.call, %b0
  br i1 true, label %cleanup1.continue, label %cleanup1.call

cleanup1.call:                                    ; preds = %cleanup0.continue
  call void @astra_test_resource_destroy(ptr null)
  br label %cleanup1.continue

cleanup1.continue:                                ; preds = %cleanup1.call, %cleanup0.continue
  ret i32 0
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

declare i32 @astra_test_resource_record_effect(i32)
