; ModuleID = 'astra.scalar'
source_filename = "astra.scalar"

define internal fastcc i32 @astra.fn.0() {
b0:
  br label %b3

b1:                                               ; preds = %b5
  ret i32 1

b2:                                               ; preds = %b5
  ret i32 0

b3:                                               ; preds = %b0
  %v1 = call fastcc i32 @astra.fn.1()
  %v2 = icmp ne i32 %v1, 42
  br i1 %v2, label %b5, label %b4

b4:                                               ; preds = %b3
  %v3 = call fastcc i32 @astra.fn.2()
  %v4 = icmp ne i32 %v3, 42
  br label %b5

b5:                                               ; preds = %b4, %b3
  %v0 = phi i1 [ true, %b3 ], [ %v4, %b4 ]
  br i1 %v0, label %b1, label %b2
}

define internal fastcc i32 @astra.fn.1() {
b0:
  %v0 = call fastcc i32 @astra.fn.3(i32 40)
  br i1 false, label %v1.trap, label %v1.valid

v1.trap:                                          ; preds = %b0
  call void @llvm.trap()
  unreachable

v1.valid:                                         ; preds = %b0
  %v3 = add i32 %v0, 2
  ret i32 %v3
}

define internal fastcc i32 @astra.fn.2() {
b0:
  %v0 = call fastcc i32 @astra.fn.3(i32 39)
  br i1 false, label %v1.trap, label %v1.valid

v1.trap:                                          ; preds = %b0
  call void @llvm.trap()
  unreachable

v1.valid:                                         ; preds = %b0
  %v3 = call fastcc i32 @astra.fn.4(i32 4, i32 3)
  %v4 = add i32 %v0, %v3
  ret i32 %v4
}

define internal fastcc i32 @astra.fn.3(i32 %p0) {
b0:
  ret i32 %p0
}

define internal fastcc i32 @astra.fn.4(i32 %p0, i32 %p1) {
b0:
  %v2 = icmp eq i32 %p0, 0
  br i1 %v2, label %b1, label %b2

b1:                                               ; preds = %b0
  ret i32 %p1

b2:                                               ; preds = %b0
  %v3 = sub i32 %p0, 1
  %v4 = call fastcc i32 @astra.fn.5(i32 %v3, i32 %p1)
  ret i32 %v4
}

define internal fastcc i32 @astra.fn.5(i32 %p0, i32 %p1) {
b0:
  %v2 = call fastcc i32 @astra.fn.4(i32 %p0, i32 %p1)
  ret i32 %v2
}

; Function Attrs: cold noreturn nounwind memory(inaccessiblemem: write)
declare void @llvm.trap() #0

attributes #0 = { cold noreturn nounwind memory(inaccessiblemem: write) }
