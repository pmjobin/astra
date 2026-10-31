; ModuleID = 'astra.scalar'
source_filename = "astra.scalar"

define internal fastcc i32 @astra.fn.0(i32 %p0, i32 %p1) {
b0:
  %v2.zero = icmp eq i32 %p1, 0
  br i1 %v2.zero, label %v2.trap, label %v2.nonzero

v2.trap:                                          ; preds = %b0
  call void @llvm.trap()
  unreachable

v2.nonzero:                                       ; preds = %b0
  %v2.minimum = icmp eq i32 %p0, -2147483648
  %v2.minusone = icmp eq i32 %p1, -1
  %v2.overflow = and i1 %v2.minimum, %v2.minusone
  br i1 %v2.overflow, label %v2.special, label %v2.normal

v2.special:                                       ; preds = %v2.nonzero
  br label %v2.continue

v2.normal:                                        ; preds = %v2.nonzero
  %v2.raw = sdiv i32 %p0, %p1
  br label %v2.continue

v2.continue:                                      ; preds = %v2.normal, %v2.special
  %v2 = phi i32 [ -2147483648, %v2.special ], [ %v2.raw, %v2.normal ]
  %v3.zero = icmp eq i32 %p1, 0
  br i1 %v3.zero, label %v3.trap, label %v3.nonzero

v3.trap:                                          ; preds = %v2.continue
  call void @llvm.trap()
  unreachable

v3.nonzero:                                       ; preds = %v2.continue
  %v3.minimum = icmp eq i32 %p0, -2147483648
  %v3.minusone = icmp eq i32 %p1, -1
  %v3.overflow = and i1 %v3.minimum, %v3.minusone
  br i1 %v3.overflow, label %v3.special, label %v3.normal

v3.special:                                       ; preds = %v3.nonzero
  br label %v3.continue

v3.normal:                                        ; preds = %v3.nonzero
  %v3.raw = srem i32 %p0, %p1
  br label %v3.continue

v3.continue:                                      ; preds = %v3.normal, %v3.special
  %v3 = phi i32 [ 0, %v3.special ], [ %v3.raw, %v3.normal ]
  %v4 = add i32 %v2, %v3
  ret i32 %v4
}

define internal fastcc i32 @astra.fn.1() {
b0:
  br i1 false, label %v0.trap, label %v0.nonzero

v0.trap:                                          ; preds = %b0
  call void @llvm.trap()
  unreachable

v0.nonzero:                                       ; preds = %b0
  br i1 true, label %v0.special, label %v0.normal

v0.special:                                       ; preds = %v0.nonzero
  br label %v0.continue

v0.normal:                                        ; preds = %v0.nonzero
  unreachable

v0.continue:                                      ; preds = %v0.special
  %v0 = phi i32 [ -2147483648, %v0.special ]
  ret i32 %v0
}

define internal fastcc i32 @astra.fn.2() {
b0:
  br i1 false, label %v0.trap, label %v0.nonzero

v0.trap:                                          ; preds = %b0
  call void @llvm.trap()
  unreachable

v0.nonzero:                                       ; preds = %b0
  br i1 true, label %v0.special, label %v0.normal

v0.special:                                       ; preds = %v0.nonzero
  br label %v0.continue

v0.normal:                                        ; preds = %v0.nonzero
  unreachable

v0.continue:                                      ; preds = %v0.special
  %v0 = phi i32 [ 0, %v0.special ]
  ret i32 %v0
}

define internal fastcc i32 @astra.fn.3() {
b0:
  br i1 true, label %v0.trap, label %v0.nonzero

v0.trap:                                          ; preds = %b0
  call void @llvm.trap()
  unreachable

v0.nonzero:                                       ; preds = %b0
  br i1 false, label %v0.special, label %v0.normal

v0.special:                                       ; preds = %v0.nonzero
  br label %v0.continue

v0.normal:                                        ; preds = %v0.nonzero
  unreachable

v0.continue:                                      ; preds = %v0.special
  %v0 = phi i32 [ -2147483648, %v0.special ]
  ret i32 %v0
}

define internal fastcc i32 @astra.fn.4() {
b0:
  br i1 true, label %v0.trap, label %v0.nonzero

v0.trap:                                          ; preds = %b0
  call void @llvm.trap()
  unreachable

v0.nonzero:                                       ; preds = %b0
  br i1 false, label %v0.special, label %v0.normal

v0.special:                                       ; preds = %v0.nonzero
  br label %v0.continue

v0.normal:                                        ; preds = %v0.nonzero
  unreachable

v0.continue:                                      ; preds = %v0.special
  %v0 = phi i32 [ 0, %v0.special ]
  ret i32 %v0
}

; Function Attrs: cold noreturn nounwind memory(inaccessiblemem: write)
declare void @llvm.trap() #0

attributes #0 = { cold noreturn nounwind memory(inaccessiblemem: write) }
