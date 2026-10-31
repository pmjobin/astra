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
  %v1 = call ptr @astra_test_resource_create(i32 2)
  %cleanup1.null = icmp eq ptr %v1, null
  br i1 %cleanup1.null, label %cleanup1.continue, label %cleanup1.call

cleanup1.call:                                    ; preds = %cleanup0.continue
  call void @astra_test_resource_destroy(ptr %v1)
  br label %cleanup1.continue

cleanup1.continue:                                ; preds = %cleanup1.call, %cleanup0.continue
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
