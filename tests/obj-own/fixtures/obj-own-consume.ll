; ModuleID = 'astra.scalar'
source_filename = "astra.scalar"

%astra.class.0 = type { i32 }

define internal fastcc void @astra.fn.0(ptr %p0) {
b0:
  %object.guard1.null = icmp eq ptr %p0, null
  br i1 %object.guard1.null, label %object.guard1.trap, label %object.guard1.nonnull

object.guard1.trap:                               ; preds = %b0
  call void @llvm.trap()
  unreachable

object.guard1.nonnull:                            ; preds = %b0
  %object.guard2.null = icmp eq ptr %p0, null
  br i1 %object.guard2.null, label %object.guard2.trap, label %object.guard2.nonnull

object.guard2.trap:                               ; preds = %object.guard1.nonnull
  call void @llvm.trap()
  unreachable

object.guard2.nonnull:                            ; preds = %object.guard1.nonnull
  %memory0.field = getelementptr inbounds nuw %astra.class.0, ptr %p0, i32 0, i32 0
  %v3 = load i32, ptr %memory0.field, align 4
  %v4 = add i32 %v3, 1
  %memory1.field = getelementptr inbounds nuw %astra.class.0, ptr %p0, i32 0, i32 0
  store i32 %v4, ptr %memory1.field, align 4
  %cleanup0.null = icmp eq ptr %p0, null
  br i1 %cleanup0.null, label %cleanup0.continue, label %cleanup0.call

cleanup0.call:                                    ; preds = %object.guard2.nonnull
  call fastcc void @astra.dtor.0(ptr %p0)
  br label %cleanup0.continue

cleanup0.continue:                                ; preds = %cleanup0.call, %object.guard2.nonnull
  ret void
}

define internal fastcc i32 @astra.fn.1() {
b0:
  %object0 = alloca %astra.class.0, align 8
  call fastcc void @astra.ctor.0(ptr %object0, i32 41)
  call fastcc void @astra.fn.0(ptr %object0)
  br i1 true, label %cleanup0.continue, label %cleanup0.call

cleanup0.call:                                    ; preds = %b0
  call fastcc void @astra.dtor.0(ptr null)
  br label %cleanup0.continue

cleanup0.continue:                                ; preds = %cleanup0.call, %b0
  ret i32 42
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

declare i32 @life_record(i32, i32)

; Function Attrs: cold noreturn nounwind memory(inaccessiblemem: write)
declare void @llvm.trap() #0

attributes #0 = { cold noreturn nounwind memory(inaccessiblemem: write) }
