; ModuleID = 'astra.scalar'
source_filename = "astra.scalar"

%astra.class.0 = type { i32 }
%astra.struct.0 = type { i32 }

define internal fastcc i32 @astra.fn.0() {
b0:
  %v0 = call fastcc i32 @astra.fn.6(i32 42)
  ret i32 %v0
}

define internal fastcc i32 @astra.fn.1() {
b0:
  %object0 = alloca %astra.class.0, align 8
  %storage0 = alloca %astra.struct.0, align 8
  %v2 = call fastcc i8 @astra.fn.7(i8 1)
  %v3 = call fastcc i8 @astra.fn.8(i8 1)
  %v4 = call fastcc i16 @astra.fn.9(i16 1)
  %v5 = call fastcc i16 @astra.fn.10(i16 1)
  %v6 = call fastcc i32 @astra.fn.6(i32 1)
  %v7 = call fastcc i32 @astra.fn.11(i32 1)
  %v10 = call fastcc <8 x i16> @astra.fn.12(<8 x i16> <i16 1, i16 2, i16 3, i16 4, i16 5, i16 6, i16 7, i16 8>)
  %v11 = call fastcc <8 x i16> @astra.fn.13(<8 x i16> <i16 1, i16 2, i16 3, i16 4, i16 5, i16 6, i16 7, i16 8>)
  %v12 = call fastcc i32 @astra.fn.14()
  %v13 = call fastcc i32 @astra.fn.15()
  %memory0.field = getelementptr inbounds nuw %astra.struct.0, ptr %storage0, i32 0, i32 0
  store i32 42, ptr %memory0.field, align 4
  call fastcc void @astra.ctor.0(ptr %object0, i32 42)
  br label %b3

b1:                                               ; preds = %b8
  ret i32 42

b2:                                               ; preds = %b8
  ret i32 1

b3:                                               ; preds = %b0
  br label %b4

b4:                                               ; preds = %b3
  %v17 = call fastcc i32 @astra.method.0.0(ptr %storage0)
  %object.guard18.null = icmp eq ptr %object0, null
  br i1 %object.guard18.null, label %object.guard18.trap, label %object.guard18.nonnull

b5:                                               ; preds = %object.guard18.nonnull
  %object.guard21.null = icmp eq ptr %object0, null
  br i1 %object.guard21.null, label %object.guard21.trap, label %object.guard21.nonnull

b6:                                               ; preds = %object.guard21.nonnull, %object.guard18.nonnull
  %v0 = phi i1 [ false, %object.guard18.nonnull ], [ %v24, %object.guard21.nonnull ]
  br i1 %v0, label %b7, label %b8

b7:                                               ; preds = %b6
  %v25 = call fastcc i32 @astra.fn.6(i32 42)
  %v26 = icmp eq i32 %v25, 42
  br label %b8

b8:                                               ; preds = %b7, %b6
  %v1 = phi i1 [ false, %b6 ], [ %v26, %b7 ]
  br i1 %v1, label %b1, label %b2

object.guard18.trap:                              ; preds = %b4
  call void @llvm.trap()
  unreachable

object.guard18.nonnull:                           ; preds = %b4
  %v19 = call fastcc i32 @astra.class.method.0.0(ptr %object0)
  %v20 = icmp eq i32 %v17, %v19
  br i1 %v20, label %b5, label %b6

object.guard21.trap:                              ; preds = %b5
  call void @llvm.trap()
  unreachable

object.guard21.nonnull:                           ; preds = %b5
  %v22 = call fastcc i32 @astra.propget.class.0.0(ptr %object0)
  %v23 = call fastcc i32 @astra.fn.0()
  %v24 = icmp eq i32 %v22, %v23
  br label %b6
}

define internal fastcc i32 @astra.method.0.0(ptr %this) {
b0:
  %memory0.field = getelementptr inbounds nuw %astra.struct.0, ptr %this, i32 0, i32 0
  %v1 = load i32, ptr %memory0.field, align 4
  %v2 = call fastcc i32 @astra.fn.6(i32 %v1)
  ret i32 %v2
}

define internal fastcc i32 @astra.class.method.0.0(ptr %this) {
b0:
  %memory0.field = getelementptr inbounds nuw %astra.class.0, ptr %this, i32 0, i32 0
  %v1 = load i32, ptr %memory0.field, align 4
  %v2 = call fastcc i32 @astra.fn.6(i32 %v1)
  ret i32 %v2
}

define internal fastcc void @astra.ctor.0(ptr %this, i32 %p0) {
b0:
  %v2 = call fastcc i32 @astra.fn.6(i32 %p0)
  %memory0.field = getelementptr inbounds nuw %astra.class.0, ptr %this, i32 0, i32 0
  store i32 %v2, ptr %memory0.field, align 4
  ret void
}

define internal fastcc i32 @astra.propget.class.0.0(ptr %this) {
b0:
  %memory0.field = getelementptr inbounds nuw %astra.class.0, ptr %this, i32 0, i32 0
  %v1 = load i32, ptr %memory0.field, align 4
  %v2 = call fastcc i32 @astra.fn.6(i32 %v1)
  ret i32 %v2
}

define internal fastcc i32 @astra.fn.6(i32 %p0) {
b0:
  ret i32 %p0
}

define internal fastcc i8 @astra.fn.7(i8 %p0) {
b0:
  ret i8 %p0
}

define internal fastcc i8 @astra.fn.8(i8 %p0) {
b0:
  ret i8 %p0
}

define internal fastcc i16 @astra.fn.9(i16 %p0) {
b0:
  ret i16 %p0
}

define internal fastcc i16 @astra.fn.10(i16 %p0) {
b0:
  ret i16 %p0
}

define internal fastcc i32 @astra.fn.11(i32 %p0) {
b0:
  ret i32 %p0
}

define internal fastcc <8 x i16> @astra.fn.12(<8 x i16> %p0) {
b0:
  ret <8 x i16> %p0
}

define internal fastcc <8 x i16> @astra.fn.13(<8 x i16> %p0) {
b0:
  ret <8 x i16> %p0
}

define internal fastcc i32 @astra.fn.14() {
b0:
  ret i32 1
}

define internal fastcc i32 @astra.fn.15() {
b0:
  ret i32 1
}

; Function Attrs: cold noreturn nounwind memory(inaccessiblemem: write)
declare void @llvm.trap() #0

attributes #0 = { cold noreturn nounwind memory(inaccessiblemem: write) }
