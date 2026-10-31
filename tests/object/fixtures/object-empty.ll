; ModuleID = 'astra.scalar'
source_filename = "astra.scalar"

%astra.class.0 = type { i8 }
%astra.class.1 = type { i8 }

define internal fastcc i32 @astra.fn.0() {
b0:
  %object0 = alloca %astra.class.0, align 8
  %object1 = alloca %astra.class.0, align 8
  %object2 = alloca %astra.class.1, align 8
  %object3 = alloca %astra.class.1, align 8
  br label %b3

b1:                                               ; preds = %b8
  ret i32 1

b2:                                               ; preds = %b8
  %v9 = icmp eq ptr %object2, %object3
  br i1 %v9, label %b9, label %b10

b3:                                               ; preds = %b0
  br label %b4

b4:                                               ; preds = %b3
  %v4 = icmp eq ptr %object0, %object1
  br i1 %v4, label %b6, label %b5

b5:                                               ; preds = %b4
  %v5 = icmp ne ptr %object0, %object0
  br label %b6

b6:                                               ; preds = %b5, %b4
  %v0 = phi i1 [ true, %b4 ], [ %v5, %b5 ]
  br i1 %v0, label %b8, label %b7

b7:                                               ; preds = %b6
  %v6 = icmp eq ptr %object0, null
  br label %b8

b8:                                               ; preds = %b7, %b6
  %v1 = phi i1 [ true, %b6 ], [ %v6, %b7 ]
  br i1 %v1, label %b1, label %b2

b9:                                               ; preds = %b2
  ret i32 2

b10:                                              ; preds = %b2
  %object.guard10.null = icmp eq ptr %object2, null
  br i1 %object.guard10.null, label %object.guard10.trap, label %object.guard10.nonnull

object.guard10.trap:                              ; preds = %b10
  call void @llvm.trap()
  unreachable

object.guard10.nonnull:                           ; preds = %b10
  %v11 = call fastcc i32 @astra.class.method.1.0(ptr %object2)
  ret i32 %v11
}

define internal fastcc i32 @astra.class.method.1.0(ptr %this) {
b0:
  ret i32 42
}

; Function Attrs: cold noreturn nounwind memory(inaccessiblemem: write)
declare void @llvm.trap() #0

attributes #0 = { cold noreturn nounwind memory(inaccessiblemem: write) }
