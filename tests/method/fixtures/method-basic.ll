; ModuleID = 'astra.scalar'
source_filename = "astra.scalar"

%astra.struct.0 = type { i32 }

define internal fastcc i32 @astra.fn.0() {
b0:
  %storage0 = alloca %astra.struct.0, align 8
  %memory0.field = getelementptr inbounds nuw %astra.struct.0, ptr %storage0, i32 0, i32 0
  store i32 40, ptr %memory0.field, align 4
  call fastcc void @astra.method.0.0(ptr %storage0, i32 2)
  %v2 = call fastcc i32 @astra.method.0.1(ptr %storage0)
  ret i32 %v2
}

define internal fastcc void @astra.method.0.0(ptr %this, i32 %p0) {
b0:
  %memory0.field = getelementptr inbounds nuw %astra.struct.0, ptr %this, i32 0, i32 0
  %v2 = load i32, ptr %memory0.field, align 4
  %v3 = add i32 %v2, %p0
  %memory1.field = getelementptr inbounds nuw %astra.struct.0, ptr %this, i32 0, i32 0
  store i32 %v3, ptr %memory1.field, align 4
  ret void
}

define internal fastcc i32 @astra.method.0.1(ptr %this) {
b0:
  %memory0.field = getelementptr inbounds nuw %astra.struct.0, ptr %this, i32 0, i32 0
  %v1 = load i32, ptr %memory0.field, align 4
  ret i32 %v1
}
