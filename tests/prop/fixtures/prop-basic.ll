; ModuleID = 'astra.scalar'
source_filename = "astra.scalar"

%astra.class.0 = type { i32 }

define internal fastcc i32 @astra.fn.0() {
b0:
  %object0 = alloca %astra.class.0, align 8
  call fastcc void @astra.ctor.0(ptr %object0, i32 1)
  %object.guard2.null = icmp eq ptr %object0, null
  br i1 %object.guard2.null, label %object.guard2.trap, label %object.guard2.nonnull

b1:                                               ; preds = %object.guard3.nonnull
  ret i32 1

b2:                                               ; preds = %object.guard3.nonnull
  %object.guard6.null = icmp eq ptr %object0, null
  br i1 %object.guard6.null, label %object.guard6.trap, label %object.guard6.nonnull

object.guard2.trap:                               ; preds = %b0
  call void @llvm.trap()
  unreachable

object.guard2.nonnull:                            ; preds = %b0
  call fastcc void @astra.propset.class.0.0(ptr %object0, i32 42)
  %object.guard3.null = icmp eq ptr %object0, null
  br i1 %object.guard3.null, label %object.guard3.trap, label %object.guard3.nonnull

object.guard3.trap:                               ; preds = %object.guard2.nonnull
  call void @llvm.trap()
  unreachable

object.guard3.nonnull:                            ; preds = %object.guard2.nonnull
  %memory0.field = getelementptr inbounds nuw %astra.class.0, ptr %object0, i32 0, i32 0
  %v4 = load i32, ptr %memory0.field, align 4
  %v5 = icmp ne i32 %v4, 42
  br i1 %v5, label %b1, label %b2

object.guard6.trap:                               ; preds = %b2
  call void @llvm.trap()
  unreachable

object.guard6.nonnull:                            ; preds = %b2
  %v7 = call fastcc i32 @astra.propget.class.0.0(ptr %object0)
  ret i32 %v7
}

define internal fastcc void @astra.ctor.0(ptr %this, i32 %p0) {
b0:
  %memory0.field = getelementptr inbounds nuw %astra.class.0, ptr %this, i32 0, i32 0
  store i32 %p0, ptr %memory0.field, align 4
  ret void
}

define internal fastcc i32 @astra.propget.class.0.0(ptr %this) {
b0:
  %memory0.field = getelementptr inbounds nuw %astra.class.0, ptr %this, i32 0, i32 0
  %v1 = load i32, ptr %memory0.field, align 4
  ret i32 %v1
}

define internal fastcc void @astra.propset.class.0.0(ptr %this, i32 %p0) {
b0:
  %memory0.field = getelementptr inbounds nuw %astra.class.0, ptr %this, i32 0, i32 0
  store i32 %p0, ptr %memory0.field, align 4
  ret void
}

; Function Attrs: cold noreturn nounwind memory(inaccessiblemem: write)
declare void @llvm.trap() #0

attributes #0 = { cold noreturn nounwind memory(inaccessiblemem: write) }
