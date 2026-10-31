; ModuleID = 'astra.scalar'
source_filename = "astra.scalar"

%astra.class.0 = type { i32 }

define internal fastcc ptr @astra.fn.0(ptr %result.storage, i32 %p0) {
b0:
  call fastcc void @astra.ctor.0(ptr %result.storage, i32 %p0)
  ret ptr %result.storage
}

define internal fastcc i32 @astra.fn.1() {
b0:
  %object0 = alloca %astra.class.0, align 8
  %v0 = call fastcc ptr @astra.fn.0(ptr %object0, i32 42)
  %object.guard1.null = icmp eq ptr %v0, null
  br i1 %object.guard1.null, label %object.guard1.trap, label %object.guard1.nonnull

object.guard1.trap:                               ; preds = %b0
  call void @llvm.trap()
  unreachable

object.guard1.nonnull:                            ; preds = %b0
  %memory0.field = getelementptr inbounds nuw %astra.class.0, ptr %v0, i32 0, i32 0
  %v2 = load i32, ptr %memory0.field, align 4
  %cleanup0.null = icmp eq ptr %v0, null
  br i1 %cleanup0.null, label %cleanup0.continue, label %cleanup0.call

cleanup0.call:                                    ; preds = %object.guard1.nonnull
  call fastcc void @astra.dtor.0(ptr %v0)
  br label %cleanup0.continue

cleanup0.continue:                                ; preds = %cleanup0.call, %object.guard1.nonnull
  ret i32 %v2
}

define internal fastcc void @astra.class.method.0.0(ptr %this, i32 %p0) {
b0:
  %memory0.field = getelementptr inbounds nuw %astra.class.0, ptr %this, i32 0, i32 0
  %v2 = load i32, ptr %memory0.field, align 4
  %v3 = add i32 %v2, %p0
  %memory1.field = getelementptr inbounds nuw %astra.class.0, ptr %this, i32 0, i32 0
  store i32 %v3, ptr %memory1.field, align 4
  ret void
}

define internal fastcc ptr @astra.class.method.0.1(ptr %result.storage, ptr %this) {
b0:
  %memory0.field = getelementptr inbounds nuw %astra.class.0, ptr %this, i32 0, i32 0
  %v1 = load i32, ptr %memory0.field, align 4
  call fastcc void @astra.ctor.0(ptr %result.storage, i32 %v1)
  ret ptr %result.storage
}

define internal fastcc void @astra.ctor.0(ptr %this, i32 %p0) {
b0:
  %memory0.field = getelementptr inbounds nuw %astra.class.0, ptr %this, i32 0, i32 0
  store i32 %p0, ptr %memory0.field, align 4
  %v2 = call i32 @life_record(i32 67, i32 0)
  ret void
}

define internal fastcc void @astra.dtor.0(ptr %this) {
b0:
  %memory0.field = getelementptr inbounds nuw %astra.class.0, ptr %this, i32 0, i32 0
  %v1 = load i32, ptr %memory0.field, align 4
  %v2 = icmp ne i32 %v1, 42
  br i1 %v2, label %b1, label %b2

b1:                                               ; preds = %b0
  %v3 = call i32 @life_record(i32 88, i32 0)
  br label %b2

b2:                                               ; preds = %b1, %b0
  %v4 = call i32 @life_record(i32 68, i32 0)
  ret void
}

declare i32 @life_record(i32, i32)

; Function Attrs: cold noreturn nounwind memory(inaccessiblemem: write)
declare void @llvm.trap() #0

attributes #0 = { cold noreturn nounwind memory(inaccessiblemem: write) }
