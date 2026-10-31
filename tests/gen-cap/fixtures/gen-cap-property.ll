; ModuleID = 'astra.scalar'
source_filename = "astra.scalar"

%astra.class.0 = type { i32 }
%astra.struct.0 = type { i32 }

define internal fastcc i32 @astra.fn.0(i32 %p0) {
b0:
  ret i32 %p0
}

define internal fastcc i32 @astra.fn.1() {
b0:
  %object0 = alloca %astra.class.0, align 8
  call fastcc void @astra.ctor.0(ptr %object0, i32 42)
  %v3 = call fastcc double @astra.fn.7(ptr %object0, double 1.250000e+00)
  br label %b3

b1:                                               ; preds = %b5
  %v8 = call fastcc i32 @astra.fn.8(ptr %object0, i32 42)
  ret i32 %v8

b2:                                               ; preds = %b5
  ret i32 1

b3:                                               ; preds = %b0
  %v4 = fcmp oeq double %v3, 1.250000e+00
  br i1 %v4, label %b4, label %b5

b4:                                               ; preds = %b3
  %object.guard5.null = icmp eq ptr %object0, null
  br i1 %object.guard5.null, label %object.guard5.trap, label %object.guard5.nonnull

b5:                                               ; preds = %object.guard5.nonnull, %b3
  %v0 = phi i1 [ false, %b3 ], [ %v7, %object.guard5.nonnull ]
  br i1 %v0, label %b1, label %b2

object.guard5.trap:                               ; preds = %b4
  call void @llvm.trap()
  unreachable

object.guard5.nonnull:                            ; preds = %b4
  %v6 = call fastcc i32 @astra.propget.class.0.0(ptr %object0)
  %v7 = icmp eq i32 %v6, 42
  br label %b5
}

define internal fastcc i32 @astra.method.0.0(ptr %this) {
b0:
  %memory0.field = getelementptr inbounds nuw %astra.struct.0, ptr %this, i32 0, i32 0
  %v1 = load i32, ptr %memory0.field, align 4
  %v2 = call fastcc i32 @astra.fn.9(i32 %v1, i32 0)
  ret i32 %v2
}

define internal fastcc i32 @astra.class.method.0.0(ptr %this) {
b0:
  %memory0.field = getelementptr inbounds nuw %astra.class.0, ptr %this, i32 0, i32 0
  %v1 = load i32, ptr %memory0.field, align 4
  %v2 = call fastcc i32 @astra.fn.9(i32 %v1, i32 0)
  ret i32 %v2
}

define internal fastcc void @astra.ctor.0(ptr %this, i32 %p0) {
b0:
  %v2 = call fastcc i32 @astra.fn.9(i32 %p0, i32 0)
  %memory0.field = getelementptr inbounds nuw %astra.class.0, ptr %this, i32 0, i32 0
  store i32 %v2, ptr %memory0.field, align 4
  ret void
}

define internal fastcc i32 @astra.propget.class.0.0(ptr %this) {
b0:
  %memory0.field = getelementptr inbounds nuw %astra.class.0, ptr %this, i32 0, i32 0
  %v1 = load i32, ptr %memory0.field, align 4
  %v2 = call fastcc i32 @astra.fn.9(i32 %v1, i32 0)
  ret i32 %v2
}

define internal fastcc void @astra.propset.class.0.0(ptr %this, i32 %p0) {
b0:
  %v2 = call fastcc i32 @astra.fn.9(i32 %p0, i32 0)
  %memory0.field = getelementptr inbounds nuw %astra.class.0, ptr %this, i32 0, i32 0
  store i32 %v2, ptr %memory0.field, align 4
  ret void
}

define internal fastcc double @astra.fn.7(ptr %p0, double %p1) {
b0:
  %storage0 = alloca %astra.struct.0, align 8
  %object.guard3.null = icmp eq ptr %p0, null
  br i1 %object.guard3.null, label %object.guard3.trap, label %object.guard3.nonnull

b1:                                               ; preds = %b5
  %object.guard14.null = icmp eq ptr %p0, null
  br i1 %object.guard14.null, label %object.guard14.trap, label %object.guard14.nonnull

b2:                                               ; preds = %object.guard14.nonnull, %b5
  %v15 = fcmp olt double %p1, %p1
  br i1 %v15, label %b6, label %b7

b3:                                               ; preds = %object.guard7.nonnull
  %v12 = icmp eq i32 %v4, %v6
  br i1 %v12, label %b4, label %b5

b4:                                               ; preds = %b3
  %v13 = icmp eq i32 %v11, %v8
  br label %b5

b5:                                               ; preds = %b4, %b3
  %v2 = phi i1 [ false, %b3 ], [ %v13, %b4 ]
  br i1 %v2, label %b1, label %b2

b6:                                               ; preds = %b2
  ret double %p1

b7:                                               ; preds = %b2
  ret double %p1

object.guard3.trap:                               ; preds = %b0
  call void @llvm.trap()
  unreachable

object.guard3.nonnull:                            ; preds = %b0
  %v4 = call fastcc i32 @astra.propget.class.0.0(ptr %p0)
  %object.guard5.null = icmp eq ptr %p0, null
  br i1 %object.guard5.null, label %object.guard5.trap, label %object.guard5.nonnull

object.guard5.trap:                               ; preds = %object.guard3.nonnull
  call void @llvm.trap()
  unreachable

object.guard5.nonnull:                            ; preds = %object.guard3.nonnull
  %v6 = call fastcc i32 @astra.class.method.0.0(ptr %p0)
  %object.guard7.null = icmp eq ptr %p0, null
  br i1 %object.guard7.null, label %object.guard7.trap, label %object.guard7.nonnull

object.guard7.trap:                               ; preds = %object.guard5.nonnull
  call void @llvm.trap()
  unreachable

object.guard7.nonnull:                            ; preds = %object.guard5.nonnull
  %memory0.field = getelementptr inbounds nuw %astra.class.0, ptr %p0, i32 0, i32 0
  %v8 = load i32, ptr %memory0.field, align 4
  %v9 = call fastcc i32 @astra.fn.0(i32 %v8)
  %memory1.field = getelementptr inbounds nuw %astra.struct.0, ptr %storage0, i32 0, i32 0
  store i32 %v9, ptr %memory1.field, align 4
  %v11 = call fastcc i32 @astra.method.0.0(ptr %storage0)
  br label %b3

object.guard14.trap:                              ; preds = %b1
  call void @llvm.trap()
  unreachable

object.guard14.nonnull:                           ; preds = %b1
  call fastcc void @astra.propset.class.0.0(ptr %p0, i32 %v9)
  br label %b2
}

define internal fastcc i32 @astra.fn.8(ptr %p0, i32 %p1) {
b0:
  %storage0 = alloca %astra.struct.0, align 8
  %object.guard3.null = icmp eq ptr %p0, null
  br i1 %object.guard3.null, label %object.guard3.trap, label %object.guard3.nonnull

b1:                                               ; preds = %b5
  %object.guard14.null = icmp eq ptr %p0, null
  br i1 %object.guard14.null, label %object.guard14.trap, label %object.guard14.nonnull

b2:                                               ; preds = %object.guard14.nonnull, %b5
  %v15 = icmp slt i32 %p1, %p1
  br i1 %v15, label %b6, label %b7

b3:                                               ; preds = %object.guard7.nonnull
  %v12 = icmp eq i32 %v4, %v6
  br i1 %v12, label %b4, label %b5

b4:                                               ; preds = %b3
  %v13 = icmp eq i32 %v11, %v8
  br label %b5

b5:                                               ; preds = %b4, %b3
  %v2 = phi i1 [ false, %b3 ], [ %v13, %b4 ]
  br i1 %v2, label %b1, label %b2

b6:                                               ; preds = %b2
  ret i32 %p1

b7:                                               ; preds = %b2
  ret i32 %p1

object.guard3.trap:                               ; preds = %b0
  call void @llvm.trap()
  unreachable

object.guard3.nonnull:                            ; preds = %b0
  %v4 = call fastcc i32 @astra.propget.class.0.0(ptr %p0)
  %object.guard5.null = icmp eq ptr %p0, null
  br i1 %object.guard5.null, label %object.guard5.trap, label %object.guard5.nonnull

object.guard5.trap:                               ; preds = %object.guard3.nonnull
  call void @llvm.trap()
  unreachable

object.guard5.nonnull:                            ; preds = %object.guard3.nonnull
  %v6 = call fastcc i32 @astra.class.method.0.0(ptr %p0)
  %object.guard7.null = icmp eq ptr %p0, null
  br i1 %object.guard7.null, label %object.guard7.trap, label %object.guard7.nonnull

object.guard7.trap:                               ; preds = %object.guard5.nonnull
  call void @llvm.trap()
  unreachable

object.guard7.nonnull:                            ; preds = %object.guard5.nonnull
  %memory0.field = getelementptr inbounds nuw %astra.class.0, ptr %p0, i32 0, i32 0
  %v8 = load i32, ptr %memory0.field, align 4
  %v9 = call fastcc i32 @astra.fn.0(i32 %v8)
  %memory1.field = getelementptr inbounds nuw %astra.struct.0, ptr %storage0, i32 0, i32 0
  store i32 %v9, ptr %memory1.field, align 4
  %v11 = call fastcc i32 @astra.method.0.0(ptr %storage0)
  br label %b3

object.guard14.trap:                              ; preds = %b1
  call void @llvm.trap()
  unreachable

object.guard14.nonnull:                           ; preds = %b1
  call fastcc void @astra.propset.class.0.0(ptr %p0, i32 %v9)
  br label %b2
}

define internal fastcc i32 @astra.fn.9(i32 %p0, i32 %p1) {
b0:
  %v2 = icmp slt i32 %p0, %p1
  br i1 %v2, label %b1, label %b2

b1:                                               ; preds = %b0
  ret i32 %p1

b2:                                               ; preds = %b0
  ret i32 %p0
}

; Function Attrs: cold noreturn nounwind memory(inaccessiblemem: write)
declare void @llvm.trap() #0

attributes #0 = { cold noreturn nounwind memory(inaccessiblemem: write) }
