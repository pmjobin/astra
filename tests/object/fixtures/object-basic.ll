; ModuleID = 'astra.scalar'
source_filename = "astra.scalar"

%astra.class.0 = type { i32 }

define internal fastcc i32 @astra.fn.0() {
b0:
  %object0 = alloca %astra.class.0, align 8
  %memory0.field = getelementptr inbounds nuw %astra.class.0, ptr %object0, i32 0, i32 0
  store i32 40, ptr %memory0.field, align 4
  %object.guard1.null = icmp eq ptr %object0, null
  br i1 %object.guard1.null, label %object.guard1.trap, label %object.guard1.nonnull

object.guard1.trap:                               ; preds = %b0
  call void @llvm.trap()
  unreachable

object.guard1.nonnull:                            ; preds = %b0
  call fastcc void @astra.class.method.0.0(ptr %object0, i32 2)
  %object.guard2.null = icmp eq ptr %object0, null
  br i1 %object.guard2.null, label %object.guard2.trap, label %object.guard2.nonnull

object.guard2.trap:                               ; preds = %object.guard1.nonnull
  call void @llvm.trap()
  unreachable

object.guard2.nonnull:                            ; preds = %object.guard1.nonnull
  %memory1.field = getelementptr inbounds nuw %astra.class.0, ptr %object0, i32 0, i32 0
  %v3 = load i32, ptr %memory1.field, align 4
  ret i32 %v3
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

; Function Attrs: cold noreturn nounwind memory(inaccessiblemem: write)
declare void @llvm.trap() #0

attributes #0 = { cold noreturn nounwind memory(inaccessiblemem: write) }
