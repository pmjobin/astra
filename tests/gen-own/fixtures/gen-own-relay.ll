; ModuleID = 'astra.scalar'
source_filename = "astra.scalar"

%astra.class.0 = type { i32 }

define internal fastcc i32 @astra.fn.0() {
b0:
  %object0 = alloca %astra.class.0, align 8
  %object1 = alloca %astra.class.0, align 8
  call fastcc void @astra.ctor.0(ptr %object0, i32 65)
  %v3 = call ptr @life_create(i32 66)
  %v4 = call fastcc ptr @astra.fn.3(ptr %object1, ptr %object0)
  %v5 = call fastcc ptr @astra.fn.4(ptr %v3)
  br label %b3

b1:                                               ; preds = %b5
  %cleanup0.null = icmp eq ptr %v5, null
  br i1 %cleanup0.null, label %cleanup0.continue, label %cleanup0.call

b2:                                               ; preds = %b5
  call fastcc void @astra.fn.5(ptr %v4)
  call fastcc void @astra.fn.6(ptr %v5)
  br i1 true, label %cleanup4.continue, label %cleanup4.call

b3:                                               ; preds = %b0
  %object.guard6.null = icmp eq ptr %v4, null
  br i1 %object.guard6.null, label %object.guard6.trap, label %object.guard6.nonnull

b4:                                               ; preds = %object.guard6.nonnull
  %v9 = call i32 @life_id(ptr %v5)
  %v10 = icmp ne i32 %v9, 66
  br label %b5

b5:                                               ; preds = %b4, %object.guard6.nonnull
  %v0 = phi i1 [ true, %object.guard6.nonnull ], [ %v10, %b4 ]
  br i1 %v0, label %b1, label %b2

object.guard6.trap:                               ; preds = %b3
  call void @llvm.trap()
  unreachable

object.guard6.nonnull:                            ; preds = %b3
  %memory0.field = getelementptr inbounds nuw %astra.class.0, ptr %v4, i32 0, i32 0
  %v7 = load i32, ptr %memory0.field, align 4
  %v8 = icmp ne i32 %v7, 65
  br i1 %v8, label %b5, label %b4

cleanup0.call:                                    ; preds = %b1
  call void @life_destroy(ptr %v5)
  br label %cleanup0.continue

cleanup0.continue:                                ; preds = %cleanup0.call, %b1
  %cleanup1.null = icmp eq ptr %v4, null
  br i1 %cleanup1.null, label %cleanup1.continue, label %cleanup1.call

cleanup1.call:                                    ; preds = %cleanup0.continue
  call fastcc void @astra.dtor.0(ptr %v4)
  br label %cleanup1.continue

cleanup1.continue:                                ; preds = %cleanup1.call, %cleanup0.continue
  br i1 true, label %cleanup2.continue, label %cleanup2.call

cleanup2.call:                                    ; preds = %cleanup1.continue
  call void @life_destroy(ptr null)
  br label %cleanup2.continue

cleanup2.continue:                                ; preds = %cleanup2.call, %cleanup1.continue
  br i1 true, label %cleanup3.continue, label %cleanup3.call

cleanup3.call:                                    ; preds = %cleanup2.continue
  call fastcc void @astra.dtor.0(ptr null)
  br label %cleanup3.continue

cleanup3.continue:                                ; preds = %cleanup3.call, %cleanup2.continue
  ret i32 1

cleanup4.call:                                    ; preds = %b2
  call void @life_destroy(ptr null)
  br label %cleanup4.continue

cleanup4.continue:                                ; preds = %cleanup4.call, %b2
  br i1 true, label %cleanup5.continue, label %cleanup5.call

cleanup5.call:                                    ; preds = %cleanup4.continue
  call fastcc void @astra.dtor.0(ptr null)
  br label %cleanup5.continue

cleanup5.continue:                                ; preds = %cleanup5.call, %cleanup4.continue
  br i1 true, label %cleanup6.continue, label %cleanup6.call

cleanup6.call:                                    ; preds = %cleanup5.continue
  call void @life_destroy(ptr null)
  br label %cleanup6.continue

cleanup6.continue:                                ; preds = %cleanup6.call, %cleanup5.continue
  br i1 true, label %cleanup7.continue, label %cleanup7.call

cleanup7.call:                                    ; preds = %cleanup6.continue
  call fastcc void @astra.dtor.0(ptr null)
  br label %cleanup7.continue

cleanup7.continue:                                ; preds = %cleanup7.call, %cleanup6.continue
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

define internal fastcc ptr @astra.fn.3(ptr %result.storage, ptr %p0) {
b0:
  %v1 = call fastcc ptr @astra.fn.7(ptr %result.storage, ptr %p0)
  br i1 true, label %cleanup0.continue, label %cleanup0.call

cleanup0.call:                                    ; preds = %b0
  call fastcc void @astra.dtor.0(ptr null)
  br label %cleanup0.continue

cleanup0.continue:                                ; preds = %cleanup0.call, %b0
  ret ptr %v1
}

define internal fastcc ptr @astra.fn.4(ptr %p0) {
b0:
  %v1 = call fastcc ptr @astra.fn.8(ptr %p0)
  br i1 true, label %cleanup0.continue, label %cleanup0.call

cleanup0.call:                                    ; preds = %b0
  call void @life_destroy(ptr null)
  br label %cleanup0.continue

cleanup0.continue:                                ; preds = %cleanup0.call, %b0
  ret ptr %v1
}

define internal fastcc void @astra.fn.5(ptr %p0) {
b0:
  %cleanup0.null = icmp eq ptr %p0, null
  br i1 %cleanup0.null, label %cleanup0.continue, label %cleanup0.call

cleanup0.call:                                    ; preds = %b0
  call fastcc void @astra.dtor.0(ptr %p0)
  br label %cleanup0.continue

cleanup0.continue:                                ; preds = %cleanup0.call, %b0
  ret void
}

define internal fastcc void @astra.fn.6(ptr %p0) {
b0:
  %cleanup0.null = icmp eq ptr %p0, null
  br i1 %cleanup0.null, label %cleanup0.continue, label %cleanup0.call

cleanup0.call:                                    ; preds = %b0
  call void @life_destroy(ptr %p0)
  br label %cleanup0.continue

cleanup0.continue:                                ; preds = %cleanup0.call, %b0
  ret void
}

define internal fastcc ptr @astra.fn.7(ptr %result.storage, ptr %p0) {
b0:
  br i1 true, label %cleanup0.continue, label %cleanup0.call

cleanup0.call:                                    ; preds = %b0
  call fastcc void @astra.dtor.0(ptr null)
  br label %cleanup0.continue

cleanup0.continue:                                ; preds = %cleanup0.call, %b0
  ret ptr %p0
}

define internal fastcc ptr @astra.fn.8(ptr %p0) {
b0:
  br i1 true, label %cleanup0.continue, label %cleanup0.call

cleanup0.call:                                    ; preds = %b0
  call void @life_destroy(ptr null)
  br label %cleanup0.continue

cleanup0.continue:                                ; preds = %cleanup0.call, %b0
  ret ptr %p0
}

declare void @life_destroy(ptr)

declare i32 @life_record(i32, i32)

declare ptr @life_create(i32)

declare ptr @own_token_create(i32)

declare i32 @life_id(ptr)

; Function Attrs: cold noreturn nounwind memory(inaccessiblemem: write)
declare void @llvm.trap() #0

attributes #0 = { cold noreturn nounwind memory(inaccessiblemem: write) }
