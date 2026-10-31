; ModuleID = 'astra.scalar'
source_filename = "astra.scalar"

%astra.struct.0 = type { i32 }

define internal fastcc i32 @astra.fn.0() {
b0:
  %storage0 = alloca %astra.struct.0, align 8
  %memory0.field = getelementptr inbounds nuw %astra.struct.0, ptr %storage0, i32 0, i32 0
  store i32 2, ptr %memory0.field, align 4
  call fastcc void @astra.propset.struct.0.0(ptr %storage0, i32 40)
  br label %b3

b1:                                               ; preds = %b5
  ret i32 1

b2:                                               ; preds = %b5
  %memory1.null = icmp eq ptr %storage0, null
  br i1 %memory1.null, label %memory1.trap, label %memory1.nonnull

b3:                                               ; preds = %b0
  br i1 false, label %b5, label %b4

b4:                                               ; preds = %b3
  %v4 = call fastcc i32 @astra.method.0.0(ptr %storage0)
  %v5 = icmp ne i32 %v4, 41
  br label %b5

b5:                                               ; preds = %b4, %b3
  %v0 = phi i1 [ true, %b3 ], [ %v5, %b4 ]
  br i1 %v0, label %b1, label %b2

memory1.trap:                                     ; preds = %b2
  call void @llvm.trap()
  unreachable

memory1.nonnull:                                  ; preds = %b2
  %memory1.field = getelementptr inbounds nuw %astra.struct.0, ptr %storage0, i32 0, i32 0
  store i32 42, ptr %memory1.field, align 4
  %v8 = call fastcc i32 @astra.propget.struct.0.0(ptr %storage0)
  ret i32 %v8
}

define internal fastcc i32 @astra.method.0.0(ptr %this) {
b0:
  %v1 = call fastcc i32 @astra.propget.struct.0.0(ptr %this)
  %v2 = add i32 %v1, 1
  call fastcc void @astra.propset.struct.0.0(ptr %this, i32 %v2)
  %memory0.field = getelementptr inbounds nuw %astra.struct.0, ptr %this, i32 0, i32 0
  %v3 = load i32, ptr %memory0.field, align 4
  ret i32 %v3
}

define internal fastcc i32 @astra.propget.struct.0.0(ptr %this) {
b0:
  %memory0.field = getelementptr inbounds nuw %astra.struct.0, ptr %this, i32 0, i32 0
  %v1 = load i32, ptr %memory0.field, align 4
  ret i32 %v1
}

define internal fastcc void @astra.propset.struct.0.0(ptr %this, i32 %p0) {
b0:
  %memory0.field = getelementptr inbounds nuw %astra.struct.0, ptr %this, i32 0, i32 0
  store i32 %p0, ptr %memory0.field, align 4
  ret void
}

; Function Attrs: cold noreturn nounwind memory(inaccessiblemem: write)
declare void @llvm.trap() #0

attributes #0 = { cold noreturn nounwind memory(inaccessiblemem: write) }
