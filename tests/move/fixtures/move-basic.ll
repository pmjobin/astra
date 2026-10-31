; ModuleID = 'astra.scalar'
source_filename = "astra.scalar"

define internal fastcc i32 @astra.fn.0() {
b0:
  %v1 = call ptr @astra_test_resource_create(i32 1)
  br label %b3

b1:                                               ; preds = %b5
  %cleanup0.null = icmp eq ptr %v1, null
  br i1 %cleanup0.null, label %cleanup0.continue, label %cleanup0.call

b2:                                               ; preds = %b5
  %cleanup2.null = icmp eq ptr %v1, null
  br i1 %cleanup2.null, label %cleanup2.continue, label %cleanup2.call

b3:                                               ; preds = %b0
  %v2 = icmp ne ptr %v1, null
  br i1 %v2, label %b4, label %b5

b4:                                               ; preds = %b3
  %v3 = icmp ne ptr null, %v1
  br label %b5

b5:                                               ; preds = %b4, %b3
  %v0 = phi i1 [ false, %b3 ], [ %v3, %b4 ]
  br i1 %v0, label %b1, label %b2

cleanup0.call:                                    ; preds = %b1
  call void @astra_test_resource_destroy(ptr %v1)
  br label %cleanup0.continue

cleanup0.continue:                                ; preds = %cleanup0.call, %b1
  br i1 true, label %cleanup1.continue, label %cleanup1.call

cleanup1.call:                                    ; preds = %cleanup0.continue
  call void @astra_test_resource_destroy(ptr null)
  br label %cleanup1.continue

cleanup1.continue:                                ; preds = %cleanup1.call, %cleanup0.continue
  ret i32 0

cleanup2.call:                                    ; preds = %b2
  call void @astra_test_resource_destroy(ptr %v1)
  br label %cleanup2.continue

cleanup2.continue:                                ; preds = %cleanup2.call, %b2
  br i1 true, label %cleanup3.continue, label %cleanup3.call

cleanup3.call:                                    ; preds = %cleanup2.continue
  call void @astra_test_resource_destroy(ptr null)
  br label %cleanup3.continue

cleanup3.continue:                                ; preds = %cleanup3.call, %cleanup2.continue
  ret i32 1
}

define internal fastcc i32 @astra.fn.1() {
b0:
  call void @astra_test_resource_reset()
  %v4 = call fastcc i32 @astra.fn.0()
  %v5 = icmp ne i32 %v4, 0
  br i1 %v5, label %b1, label %b2

b1:                                               ; preds = %b0
  ret i32 1

b2:                                               ; preds = %b0
  br label %b5

b3:                                               ; preds = %b16
  ret i32 2

b4:                                               ; preds = %b16
  ret i32 0

b5:                                               ; preds = %b2
  br label %b6

b6:                                               ; preds = %b5
  br label %b7

b7:                                               ; preds = %b6
  br label %b8

b8:                                               ; preds = %b7
  %v6 = call i32 @astra_test_resource_create_count()
  %v7 = icmp ne i32 %v6, 1
  br i1 %v7, label %b10, label %b9

b9:                                               ; preds = %b8
  %v8 = call i32 @astra_test_resource_destroy_count()
  %v9 = icmp ne i32 %v8, 1
  br label %b10

b10:                                              ; preds = %b9, %b8
  %v0 = phi i1 [ true, %b8 ], [ %v9, %b9 ]
  br i1 %v0, label %b12, label %b11

b11:                                              ; preds = %b10
  %v10 = call i32 @astra_test_resource_destroy_order()
  %v11 = icmp ne i32 %v10, 1
  br label %b12

b12:                                              ; preds = %b11, %b10
  %v1 = phi i1 [ true, %b10 ], [ %v11, %b11 ]
  br i1 %v1, label %b14, label %b13

b13:                                              ; preds = %b12
  %v12 = call i32 @astra_test_resource_live_count()
  %v13 = icmp ne i32 %v12, 0
  br label %b14

b14:                                              ; preds = %b13, %b12
  %v2 = phi i1 [ true, %b12 ], [ %v13, %b13 ]
  br i1 %v2, label %b16, label %b15

b15:                                              ; preds = %b14
  %v14 = call i32 @astra_test_resource_error_count()
  %v15 = icmp ne i32 %v14, 0
  br label %b16

b16:                                              ; preds = %b15, %b14
  %v3 = phi i1 [ true, %b14 ], [ %v15, %b15 ]
  br i1 %v3, label %b3, label %b4
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
