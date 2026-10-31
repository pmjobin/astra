; ModuleID = 'astra.scalar'
source_filename = "astra.scalar"

%astra.class.0 = type { i32 }

define internal fastcc i32 @astra.fn.0() {
b0:
  %object0 = alloca %astra.class.0, align 8
  call fastcc void @astra.ctor.0(ptr %object0, i32 1)
  %object.guard3.null = icmp eq ptr %object0, null
  br i1 %object.guard3.null, label %object.guard3.trap, label %object.guard3.nonnull

b1:                                               ; preds = %b5
  call fastcc void @astra.dtor.0(ptr %object0)
  ret i32 1

b2:                                               ; preds = %b5
  %object.guard8.null = icmp eq ptr %object0, null
  br i1 %object.guard8.null, label %object.guard8.trap, label %object.guard8.nonnull

b3:                                               ; preds = %object.guard4.nonnull
  %v5 = icmp ne ptr %object0, %object0
  br i1 %v5, label %b5, label %b4

b4:                                               ; preds = %b3
  br label %b5

b5:                                               ; preds = %b4, %b3
  %v0 = phi i1 [ true, %b3 ], [ false, %b4 ]
  br i1 %v0, label %b1, label %b2

object.guard3.trap:                               ; preds = %b0
  call void @llvm.trap()
  unreachable

object.guard3.nonnull:                            ; preds = %b0
  call fastcc void @astra.class.method.0.0(ptr %object0, i32 40)
  %object.guard4.null = icmp eq ptr %object0, null
  br i1 %object.guard4.null, label %object.guard4.trap, label %object.guard4.nonnull

object.guard4.trap:                               ; preds = %object.guard3.nonnull
  call void @llvm.trap()
  unreachable

object.guard4.nonnull:                            ; preds = %object.guard3.nonnull
  %memory0.field = getelementptr inbounds nuw %astra.class.0, ptr %object0, i32 0, i32 0
  store i32 42, ptr %memory0.field, align 4
  br label %b3

object.guard8.trap:                               ; preds = %b2
  call void @llvm.trap()
  unreachable

object.guard8.nonnull:                            ; preds = %b2
  %memory1.field = getelementptr inbounds nuw %astra.class.0, ptr %object0, i32 0, i32 0
  %v9 = load i32, ptr %memory1.field, align 4
  call fastcc void @astra.dtor.0(ptr %object0)
  ret i32 %v9
}

define internal fastcc void @astra.class.method.0.0(ptr %this, i32 %p0) {
b0:
  %memory0.field = getelementptr inbounds nuw %astra.class.0, ptr %this, i32 0, i32 0
  store i32 %p0, ptr %memory0.field, align 4
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
