; ModuleID = 'astra.scalar'
source_filename = "astra.scalar"

define internal fastcc i32 @astra.fn.0(ptr %p0) {
b0:
  %v1 = call i32 @astra_test_resource_is_live(ptr %p0)
  ret i32 %v1
}

define internal fastcc void @astra.fn.1() {
b0:
  %v0 = call ptr @astra_test_resource_create(i32 1)
  %v1 = call fastcc i32 @astra.fn.0(ptr %v0)
  %v2 = call i32 @astra_test_resource_is_live(ptr %v0)
  %cleanup0.null = icmp eq ptr %v0, null
  br i1 %cleanup0.null, label %cleanup0.continue, label %cleanup0.call

cleanup0.call:                                    ; preds = %b0
  call void @astra_test_resource_destroy(ptr %v0)
  br label %cleanup0.continue

cleanup0.continue:                                ; preds = %cleanup0.call, %b0
  br i1 true, label %cleanup1.continue, label %cleanup1.call

cleanup1.call:                                    ; preds = %cleanup0.continue
  call void @astra_test_resource_destroy(ptr null)
  br label %cleanup1.continue

cleanup1.continue:                                ; preds = %cleanup1.call, %cleanup0.continue
  ret void
}

declare void @astra_test_resource_destroy(ptr)

declare ptr @astra_test_resource_create(i32)

declare i32 @astra_test_resource_is_live(ptr)
