; ModuleID = 'astra.scalar'
source_filename = "astra.scalar"

%astra.class.0 = type { i32 }

define internal fastcc i32 @astra.fn.0() {
b0:
  %v0 = call ptr @life_create(i32 65)
  %v1 = call ptr @own_token_create(i32 66)
  call fastcc void @astra.fn.3(ptr %v0)
  call fastcc void @astra.fn.4(ptr %v1)
  br i1 true, label %cleanup0.continue, label %cleanup0.call

cleanup0.call:                                    ; preds = %b0
  call void @life_destroy(ptr null)
  br label %cleanup0.continue

cleanup0.continue:                                ; preds = %cleanup0.call, %b0
  br i1 true, label %cleanup1.continue, label %cleanup1.call

cleanup1.call:                                    ; preds = %cleanup0.continue
  call void @life_destroy(ptr null)
  br label %cleanup1.continue

cleanup1.continue:                                ; preds = %cleanup1.call, %cleanup0.continue
  ret i32 42
}

define internal fastcc void @astra.ctor.0(ptr %this, i32 %p0) {
b0:
  %memory0.field = getelementptr inbounds nuw %astra.class.0, ptr %this, i32 0, i32 0
  store i32 %p0, ptr %memory0.field, align 4
  ret void
}

define internal fastcc void @astra.dtor.0(ptr %this) {
b0:
  %memory0.field = getelementptr inbounds nuw %astra.class.0, ptr %this, i32 0, i32 0
  %v1 = load i32, ptr %memory0.field, align 4
  %v2 = call i32 @life_record(i32 %v1, i32 0)
  ret void
}

define internal fastcc void @astra.fn.3(ptr %p0) {
b0:
  %cleanup0.null = icmp eq ptr %p0, null
  br i1 %cleanup0.null, label %cleanup0.continue, label %cleanup0.call

cleanup0.call:                                    ; preds = %b0
  call void @life_destroy(ptr %p0)
  br label %cleanup0.continue

cleanup0.continue:                                ; preds = %cleanup0.call, %b0
  ret void
}

define internal fastcc void @astra.fn.4(ptr %p0) {
b0:
  %cleanup0.null = icmp eq ptr %p0, null
  br i1 %cleanup0.null, label %cleanup0.continue, label %cleanup0.call

cleanup0.call:                                    ; preds = %b0
  call void @life_destroy(ptr %p0)
  br label %cleanup0.continue

cleanup0.continue:                                ; preds = %cleanup0.call, %b0
  ret void
}

declare void @life_destroy(ptr)

declare i32 @life_record(i32, i32)

declare ptr @life_create(i32)

declare ptr @own_token_create(i32)

declare i32 @life_id(ptr)
