; ModuleID = 'astra.scalar'
source_filename = "astra.scalar"

%astra.class.0 = type { i32 }

define internal fastcc i32 @astra.fn.0() {
b0:
  %object0 = alloca %astra.class.0, align 8
  %object1 = alloca %astra.class.0, align 8
  %object2 = alloca %astra.class.0, align 8
  %v1 = call ptr @life_create(i32 65)
  %v2 = call fastcc ptr @astra.fn.3(i32 5, ptr %v1)
  %v3 = call fastcc ptr @astra.fn.4(i32 4, ptr %v2)
  call fastcc void @astra.ctor.0(ptr %object0, i32 66)
  %v6 = call fastcc ptr @astra.fn.5(ptr %object1, i32 5, ptr %object0)
  %v7 = call fastcc ptr @astra.fn.6(ptr %object2, i32 4, ptr %v6)
  br label %b3

b1:                                               ; preds = %b5
  %cleanup0.null = icmp eq ptr %v7, null
  br i1 %cleanup0.null, label %cleanup0.continue, label %cleanup0.call

b2:                                               ; preds = %b5
  call fastcc void @astra.fn.7(ptr %v3)
  call fastcc void @astra.fn.8(ptr %v7)
  br i1 true, label %cleanup6.continue, label %cleanup6.call

b3:                                               ; preds = %b0
  %v8 = call i32 @life_id(ptr %v3)
  %v9 = icmp ne i32 %v8, 65
  br i1 %v9, label %b5, label %b4

b4:                                               ; preds = %b3
  %object.guard10.null = icmp eq ptr %v7, null
  br i1 %object.guard10.null, label %object.guard10.trap, label %object.guard10.nonnull

b5:                                               ; preds = %object.guard10.nonnull, %b3
  %v0 = phi i1 [ true, %b3 ], [ %v12, %object.guard10.nonnull ]
  br i1 %v0, label %b1, label %b2

cleanup0.call:                                    ; preds = %b1
  call fastcc void @astra.dtor.0(ptr %v7)
  br label %cleanup0.continue

cleanup0.continue:                                ; preds = %cleanup0.call, %b1
  br i1 true, label %cleanup1.continue, label %cleanup1.call

cleanup1.call:                                    ; preds = %cleanup0.continue
  call fastcc void @astra.dtor.0(ptr null)
  br label %cleanup1.continue

cleanup1.continue:                                ; preds = %cleanup1.call, %cleanup0.continue
  br i1 true, label %cleanup2.continue, label %cleanup2.call

cleanup2.call:                                    ; preds = %cleanup1.continue
  call fastcc void @astra.dtor.0(ptr null)
  br label %cleanup2.continue

cleanup2.continue:                                ; preds = %cleanup2.call, %cleanup1.continue
  %cleanup3.null = icmp eq ptr %v3, null
  br i1 %cleanup3.null, label %cleanup3.continue, label %cleanup3.call

cleanup3.call:                                    ; preds = %cleanup2.continue
  call void @life_destroy(ptr %v3)
  br label %cleanup3.continue

cleanup3.continue:                                ; preds = %cleanup3.call, %cleanup2.continue
  br i1 true, label %cleanup4.continue, label %cleanup4.call

cleanup4.call:                                    ; preds = %cleanup3.continue
  call void @life_destroy(ptr null)
  br label %cleanup4.continue

cleanup4.continue:                                ; preds = %cleanup4.call, %cleanup3.continue
  br i1 true, label %cleanup5.continue, label %cleanup5.call

cleanup5.call:                                    ; preds = %cleanup4.continue
  call void @life_destroy(ptr null)
  br label %cleanup5.continue

cleanup5.continue:                                ; preds = %cleanup5.call, %cleanup4.continue
  ret i32 1

cleanup6.call:                                    ; preds = %b2
  call fastcc void @astra.dtor.0(ptr null)
  br label %cleanup6.continue

cleanup6.continue:                                ; preds = %cleanup6.call, %b2
  br i1 true, label %cleanup7.continue, label %cleanup7.call

cleanup7.call:                                    ; preds = %cleanup6.continue
  call fastcc void @astra.dtor.0(ptr null)
  br label %cleanup7.continue

cleanup7.continue:                                ; preds = %cleanup7.call, %cleanup6.continue
  br i1 true, label %cleanup8.continue, label %cleanup8.call

cleanup8.call:                                    ; preds = %cleanup7.continue
  call fastcc void @astra.dtor.0(ptr null)
  br label %cleanup8.continue

cleanup8.continue:                                ; preds = %cleanup8.call, %cleanup7.continue
  br i1 true, label %cleanup9.continue, label %cleanup9.call

cleanup9.call:                                    ; preds = %cleanup8.continue
  call void @life_destroy(ptr null)
  br label %cleanup9.continue

cleanup9.continue:                                ; preds = %cleanup9.call, %cleanup8.continue
  br i1 true, label %cleanup10.continue, label %cleanup10.call

cleanup10.call:                                   ; preds = %cleanup9.continue
  call void @life_destroy(ptr null)
  br label %cleanup10.continue

cleanup10.continue:                               ; preds = %cleanup10.call, %cleanup9.continue
  br i1 true, label %cleanup11.continue, label %cleanup11.call

cleanup11.call:                                   ; preds = %cleanup10.continue
  call void @life_destroy(ptr null)
  br label %cleanup11.continue

cleanup11.continue:                               ; preds = %cleanup11.call, %cleanup10.continue
  ret i32 42

object.guard10.trap:                              ; preds = %b4
  call void @llvm.trap()
  unreachable

object.guard10.nonnull:                           ; preds = %b4
  %memory0.field = getelementptr inbounds nuw %astra.class.0, ptr %v7, i32 0, i32 0
  %v11 = load i32, ptr %memory0.field, align 4
  %v12 = icmp ne i32 %v11, 66
  br label %b5
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

define internal fastcc ptr @astra.fn.3(i32 %p0, ptr %p1) {
b0:
  %v2 = icmp eq i32 %p0, 0
  br i1 %v2, label %b1, label %b2

b1:                                               ; preds = %b0
  br i1 true, label %cleanup0.continue, label %cleanup0.call

b2:                                               ; preds = %b0
  %v3 = sub i32 %p0, 1
  %v4 = call fastcc ptr @astra.fn.3(i32 %v3, ptr %p1)
  br i1 true, label %cleanup1.continue, label %cleanup1.call

cleanup0.call:                                    ; preds = %b1
  call void @life_destroy(ptr null)
  br label %cleanup0.continue

cleanup0.continue:                                ; preds = %cleanup0.call, %b1
  ret ptr %p1

cleanup1.call:                                    ; preds = %b2
  call void @life_destroy(ptr null)
  br label %cleanup1.continue

cleanup1.continue:                                ; preds = %cleanup1.call, %b2
  ret ptr %v4
}

define internal fastcc ptr @astra.fn.4(i32 %p0, ptr %p1) {
b0:
  %v2 = icmp eq i32 %p0, 0
  br i1 %v2, label %b1, label %b2

b1:                                               ; preds = %b0
  br i1 true, label %cleanup0.continue, label %cleanup0.call

b2:                                               ; preds = %b0
  %v3 = sub i32 %p0, 1
  %v4 = call fastcc ptr @astra.fn.9(i32 %v3, ptr %p1)
  br i1 true, label %cleanup1.continue, label %cleanup1.call

cleanup0.call:                                    ; preds = %b1
  call void @life_destroy(ptr null)
  br label %cleanup0.continue

cleanup0.continue:                                ; preds = %cleanup0.call, %b1
  ret ptr %p1

cleanup1.call:                                    ; preds = %b2
  call void @life_destroy(ptr null)
  br label %cleanup1.continue

cleanup1.continue:                                ; preds = %cleanup1.call, %b2
  ret ptr %v4
}

define internal fastcc ptr @astra.fn.5(ptr %result.storage, i32 %p0, ptr %p1) {
b0:
  %v2 = icmp eq i32 %p0, 0
  br i1 %v2, label %b1, label %b2

b1:                                               ; preds = %b0
  br i1 true, label %cleanup0.continue, label %cleanup0.call

b2:                                               ; preds = %b0
  %v3 = sub i32 %p0, 1
  %v4 = call fastcc ptr @astra.fn.5(ptr %result.storage, i32 %v3, ptr %p1)
  br i1 true, label %cleanup1.continue, label %cleanup1.call

cleanup0.call:                                    ; preds = %b1
  call fastcc void @astra.dtor.0(ptr null)
  br label %cleanup0.continue

cleanup0.continue:                                ; preds = %cleanup0.call, %b1
  ret ptr %p1

cleanup1.call:                                    ; preds = %b2
  call fastcc void @astra.dtor.0(ptr null)
  br label %cleanup1.continue

cleanup1.continue:                                ; preds = %cleanup1.call, %b2
  ret ptr %v4
}

define internal fastcc ptr @astra.fn.6(ptr %result.storage, i32 %p0, ptr %p1) {
b0:
  %v2 = icmp eq i32 %p0, 0
  br i1 %v2, label %b1, label %b2

b1:                                               ; preds = %b0
  br i1 true, label %cleanup0.continue, label %cleanup0.call

b2:                                               ; preds = %b0
  %v3 = sub i32 %p0, 1
  %v4 = call fastcc ptr @astra.fn.10(ptr %result.storage, i32 %v3, ptr %p1)
  br i1 true, label %cleanup1.continue, label %cleanup1.call

cleanup0.call:                                    ; preds = %b1
  call fastcc void @astra.dtor.0(ptr null)
  br label %cleanup0.continue

cleanup0.continue:                                ; preds = %cleanup0.call, %b1
  ret ptr %p1

cleanup1.call:                                    ; preds = %b2
  call fastcc void @astra.dtor.0(ptr null)
  br label %cleanup1.continue

cleanup1.continue:                                ; preds = %cleanup1.call, %b2
  ret ptr %v4
}

define internal fastcc void @astra.fn.7(ptr %p0) {
b0:
  %cleanup0.null = icmp eq ptr %p0, null
  br i1 %cleanup0.null, label %cleanup0.continue, label %cleanup0.call

cleanup0.call:                                    ; preds = %b0
  call void @life_destroy(ptr %p0)
  br label %cleanup0.continue

cleanup0.continue:                                ; preds = %cleanup0.call, %b0
  ret void
}

define internal fastcc void @astra.fn.8(ptr %p0) {
b0:
  %cleanup0.null = icmp eq ptr %p0, null
  br i1 %cleanup0.null, label %cleanup0.continue, label %cleanup0.call

cleanup0.call:                                    ; preds = %b0
  call fastcc void @astra.dtor.0(ptr %p0)
  br label %cleanup0.continue

cleanup0.continue:                                ; preds = %cleanup0.call, %b0
  ret void
}

define internal fastcc ptr @astra.fn.9(i32 %p0, ptr %p1) {
b0:
  %v2 = call fastcc ptr @astra.fn.4(i32 %p0, ptr %p1)
  br i1 true, label %cleanup0.continue, label %cleanup0.call

cleanup0.call:                                    ; preds = %b0
  call void @life_destroy(ptr null)
  br label %cleanup0.continue

cleanup0.continue:                                ; preds = %cleanup0.call, %b0
  ret ptr %v2
}

define internal fastcc ptr @astra.fn.10(ptr %result.storage, i32 %p0, ptr %p1) {
b0:
  %v2 = call fastcc ptr @astra.fn.6(ptr %result.storage, i32 %p0, ptr %p1)
  br i1 true, label %cleanup0.continue, label %cleanup0.call

cleanup0.call:                                    ; preds = %b0
  call fastcc void @astra.dtor.0(ptr null)
  br label %cleanup0.continue

cleanup0.continue:                                ; preds = %cleanup0.call, %b0
  ret ptr %v2
}

declare void @life_destroy(ptr)

declare i32 @life_record(i32, i32)

declare ptr @life_create(i32)

declare ptr @own_token_create(i32)

declare i32 @life_id(ptr)

; Function Attrs: cold noreturn nounwind memory(inaccessiblemem: write)
declare void @llvm.trap() #0

attributes #0 = { cold noreturn nounwind memory(inaccessiblemem: write) }
