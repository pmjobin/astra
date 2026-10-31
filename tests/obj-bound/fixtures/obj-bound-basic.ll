; ModuleID = 'astra.scalar'
source_filename = "astra.scalar"

%astra.class.0 = type { i32 }

define internal fastcc i32 @astra.fn.0(ptr %p0) {
b0:
  %object.guard1.null = icmp eq ptr %p0, null
  br i1 %object.guard1.null, label %object.guard1.trap, label %object.guard1.nonnull

object.guard1.trap:                               ; preds = %b0
  call void @llvm.trap()
  unreachable

object.guard1.nonnull:                            ; preds = %b0
  %memory0.field = getelementptr inbounds nuw %astra.class.0, ptr %p0, i32 0, i32 0
  %v2 = load i32, ptr %memory0.field, align 4
  ret i32 %v2
}

define internal fastcc i32 @astra.fn.1() {
b0:
  %object0 = alloca %astra.class.0, align 8
  %memory0.field = getelementptr inbounds nuw %astra.class.0, ptr %object0, i32 0, i32 0
  store i32 42, ptr %memory0.field, align 4
  br label %b3

b1:                                               ; preds = %b5
  ret i32 1

b2:                                               ; preds = %b5
  %object.guard5.null = icmp eq ptr %object0, null
  br i1 %object.guard5.null, label %object.guard5.trap, label %object.guard5.nonnull

b3:                                               ; preds = %b0
  %v2 = call fastcc i32 @astra.fn.0(ptr %object0)
  %v3 = icmp ne i32 %v2, 42
  br i1 %v3, label %b5, label %b4

b4:                                               ; preds = %b3
  %v4 = icmp ne ptr %object0, %object0
  br label %b5

b5:                                               ; preds = %b4, %b3
  %v0 = phi i1 [ true, %b3 ], [ %v4, %b4 ]
  br i1 %v0, label %b1, label %b2

object.guard5.trap:                               ; preds = %b2
  call void @llvm.trap()
  unreachable

object.guard5.nonnull:                            ; preds = %b2
  %memory1.field = getelementptr inbounds nuw %astra.class.0, ptr %object0, i32 0, i32 0
  %v6 = load i32, ptr %memory1.field, align 4
  ret i32 %v6
}

; Function Attrs: cold noreturn nounwind memory(inaccessiblemem: write)
declare void @llvm.trap() #0

attributes #0 = { cold noreturn nounwind memory(inaccessiblemem: write) }
