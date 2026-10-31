; ModuleID = 'astra.scalar'
source_filename = "astra.scalar"

%astra.class.0 = type { double }

define internal fastcc double @astra.fn.0(ptr %p0) {
b0:
  %object.guard1.null = icmp eq ptr %p0, null
  br i1 %object.guard1.null, label %object.guard1.trap, label %object.guard1.nonnull

b1:                                               ; preds = %object.guard1.nonnull
  %object.guard4.null = icmp eq ptr %p0, null
  br i1 %object.guard4.null, label %object.guard4.trap, label %object.guard4.nonnull

b2:                                               ; preds = %object.guard1.nonnull
  ret double 0.000000e+00

object.guard1.trap:                               ; preds = %b0
  call void @llvm.trap()
  unreachable

object.guard1.nonnull:                            ; preds = %b0
  %v2 = call fastcc double @astra.propget.class.0.0(ptr %p0)
  %v3 = fcmp oeq double 0x3FF0000000000001, %v2
  br i1 %v3, label %b1, label %b2

object.guard4.trap:                               ; preds = %b1
  call void @llvm.trap()
  unreachable

object.guard4.nonnull:                            ; preds = %b1
  %v5 = call fastcc double @astra.propget.class.0.0(ptr %p0)
  ret double %v5
}

define internal fastcc i32 @astra.fn.1() {
b0:
  %object0 = alloca %astra.class.0, align 8
  %memory0.field = getelementptr inbounds nuw %astra.class.0, ptr %object0, i32 0, i32 0
  store double 0.000000e+00, ptr %memory0.field, align 8
  %object.guard3.null = icmp eq ptr %object0, null
  br i1 %object.guard3.null, label %object.guard3.trap, label %object.guard3.nonnull

b1:                                               ; preds = %b5
  ret i32 1

b2:                                               ; preds = %b5
  %object.guard11.null = icmp eq ptr %object0, null
  br i1 %object.guard11.null, label %object.guard11.trap, label %object.guard11.nonnull

b3:                                               ; preds = %object.guard3.nonnull
  %object.guard4.null = icmp eq ptr %object0, null
  br i1 %object.guard4.null, label %object.guard4.trap, label %object.guard4.nonnull

b4:                                               ; preds = %object.guard4.nonnull
  %v7 = call fastcc double @astra.fn.0(ptr %object0)
  %object.guard8.null = icmp eq ptr %object0, null
  br i1 %object.guard8.null, label %object.guard8.trap, label %object.guard8.nonnull

b5:                                               ; preds = %object.guard8.nonnull, %object.guard4.nonnull
  %v0 = phi i1 [ true, %object.guard4.nonnull ], [ %v10, %object.guard8.nonnull ]
  br i1 %v0, label %b1, label %b2

b6:                                               ; preds = %object.guard12.nonnull
  ret i32 2

b7:                                               ; preds = %object.guard12.nonnull
  %object.guard16.null = icmp eq ptr %object0, null
  br i1 %object.guard16.null, label %object.guard16.trap, label %object.guard16.nonnull

b8:                                               ; preds = %object.guard17.nonnull
  ret i32 3

b9:                                               ; preds = %object.guard17.nonnull
  %object.guard20.null = icmp eq ptr %object0, null
  br i1 %object.guard20.null, label %object.guard20.trap, label %object.guard20.nonnull

b10:                                              ; preds = %object.guard21.nonnull
  ret i32 4

b11:                                              ; preds = %object.guard21.nonnull
  %object.guard24.null = icmp eq ptr %object0, null
  br i1 %object.guard24.null, label %object.guard24.trap, label %object.guard24.nonnull

b12:                                              ; preds = %b16
  ret i32 5

b13:                                              ; preds = %b16
  %object.guard37.null = icmp eq ptr %object0, null
  br i1 %object.guard37.null, label %object.guard37.trap, label %object.guard37.nonnull

b14:                                              ; preds = %object.guard24.nonnull
  %object.guard26.null = icmp eq ptr %object0, null
  br i1 %object.guard26.null, label %object.guard26.trap, label %object.guard26.nonnull

b15:                                              ; preds = %object.guard28.nonnull
  %object.guard31.null = icmp eq ptr %object0, null
  br i1 %object.guard31.null, label %object.guard31.trap, label %object.guard31.nonnull

b16:                                              ; preds = %object.guard33.nonnull, %object.guard28.nonnull
  %v1 = phi i1 [ true, %object.guard28.nonnull ], [ %v36, %object.guard33.nonnull ]
  br i1 %v1, label %b12, label %b13

b17:                                              ; preds = %object.guard38.nonnull
  ret i32 6

b18:                                              ; preds = %object.guard38.nonnull
  ret i32 42

object.guard3.trap:                               ; preds = %b0
  call void @llvm.trap()
  unreachable

object.guard3.nonnull:                            ; preds = %b0
  call fastcc void @astra.propset.class.0.0(ptr %object0, double 0x3FF0000000000001)
  br label %b3

object.guard4.trap:                               ; preds = %b3
  call void @llvm.trap()
  unreachable

object.guard4.nonnull:                            ; preds = %b3
  %v5 = call fastcc double @astra.propget.class.0.0(ptr %object0)
  %v6 = fcmp une double %v5, 0x3FF0000000000001
  br i1 %v6, label %b5, label %b4

object.guard11.trap:                              ; preds = %b2
  call void @llvm.trap()
  unreachable

object.guard11.nonnull:                           ; preds = %b2
  call fastcc void @astra.propset.class.0.0(ptr %object0, double -0.000000e+00)
  %object.guard12.null = icmp eq ptr %object0, null
  br i1 %object.guard12.null, label %object.guard12.trap, label %object.guard12.nonnull

object.guard12.trap:                              ; preds = %object.guard11.nonnull
  call void @llvm.trap()
  unreachable

object.guard12.nonnull:                           ; preds = %object.guard11.nonnull
  %v13 = call fastcc double @astra.propget.class.0.0(ptr %object0)
  %v14 = fdiv double 1.000000e+00, %v13
  %v15 = fcmp oge double %v14, 0.000000e+00
  br i1 %v15, label %b6, label %b7

object.guard16.trap:                              ; preds = %b7
  call void @llvm.trap()
  unreachable

object.guard16.nonnull:                           ; preds = %b7
  call fastcc void @astra.propset.class.0.0(ptr %object0, double 4.940660e-324)
  %object.guard17.null = icmp eq ptr %object0, null
  br i1 %object.guard17.null, label %object.guard17.trap, label %object.guard17.nonnull

object.guard17.trap:                              ; preds = %object.guard16.nonnull
  call void @llvm.trap()
  unreachable

object.guard17.nonnull:                           ; preds = %object.guard16.nonnull
  %v18 = call fastcc double @astra.propget.class.0.0(ptr %object0)
  %v19 = fcmp une double %v18, 4.940660e-324
  br i1 %v19, label %b8, label %b9

object.guard20.trap:                              ; preds = %b9
  call void @llvm.trap()
  unreachable

object.guard20.nonnull:                           ; preds = %b9
  call fastcc void @astra.propset.class.0.0(ptr %object0, double 0x7FF0000000000000)
  %object.guard21.null = icmp eq ptr %object0, null
  br i1 %object.guard21.null, label %object.guard21.trap, label %object.guard21.nonnull

object.guard21.trap:                              ; preds = %object.guard20.nonnull
  call void @llvm.trap()
  unreachable

object.guard21.nonnull:                           ; preds = %object.guard20.nonnull
  %v22 = call fastcc double @astra.propget.class.0.0(ptr %object0)
  %v23 = fcmp une double %v22, 0x7FF0000000000000
  br i1 %v23, label %b10, label %b11

object.guard24.trap:                              ; preds = %b11
  call void @llvm.trap()
  unreachable

object.guard24.nonnull:                           ; preds = %b11
  call fastcc void @astra.propset.class.0.0(ptr %object0, double 0x7FF8000000000000)
  br label %b14

object.guard26.trap:                              ; preds = %b14
  call void @llvm.trap()
  unreachable

object.guard26.nonnull:                           ; preds = %b14
  %v27 = call fastcc double @astra.propget.class.0.0(ptr %object0)
  %object.guard28.null = icmp eq ptr %object0, null
  br i1 %object.guard28.null, label %object.guard28.trap, label %object.guard28.nonnull

object.guard28.trap:                              ; preds = %object.guard26.nonnull
  call void @llvm.trap()
  unreachable

object.guard28.nonnull:                           ; preds = %object.guard26.nonnull
  %v29 = call fastcc double @astra.propget.class.0.0(ptr %object0)
  %v30 = fcmp oeq double %v27, %v29
  br i1 %v30, label %b16, label %b15

object.guard37.trap:                              ; preds = %b13
  call void @llvm.trap()
  unreachable

object.guard37.nonnull:                           ; preds = %b13
  call fastcc void @astra.propset.class.0.0(ptr %object0, double -1.000000e+00)
  %object.guard38.null = icmp eq ptr %object0, null
  br i1 %object.guard38.null, label %object.guard38.trap, label %object.guard38.nonnull

object.guard38.trap:                              ; preds = %object.guard37.nonnull
  call void @llvm.trap()
  unreachable

object.guard38.nonnull:                           ; preds = %object.guard37.nonnull
  %v39 = call fastcc double @astra.class.method.0.0(ptr %object0, double 0x3FF0000002000000, double 0x3FEFFFFFFC000000)
  %v40 = fcmp une double %v39, 0.000000e+00
  br i1 %v40, label %b17, label %b18

object.guard31.trap:                              ; preds = %b15
  call void @llvm.trap()
  unreachable

object.guard31.nonnull:                           ; preds = %b15
  %v32 = call fastcc double @astra.propget.class.0.0(ptr %object0)
  %object.guard33.null = icmp eq ptr %object0, null
  br i1 %object.guard33.null, label %object.guard33.trap, label %object.guard33.nonnull

object.guard33.trap:                              ; preds = %object.guard31.nonnull
  call void @llvm.trap()
  unreachable

object.guard33.nonnull:                           ; preds = %object.guard31.nonnull
  %v34 = call fastcc double @astra.propget.class.0.0(ptr %object0)
  %v35 = fcmp une double %v32, %v34
  %v36 = xor i1 %v35, true
  br label %b16

object.guard8.trap:                               ; preds = %b4
  call void @llvm.trap()
  unreachable

object.guard8.nonnull:                            ; preds = %b4
  %memory1.field = getelementptr inbounds nuw %astra.class.0, ptr %object0, i32 0, i32 0
  %v9 = load double, ptr %memory1.field, align 8
  %v10 = fcmp une double %v7, %v9
  br label %b5
}

define internal fastcc double @astra.class.method.0.0(ptr %this, double %p0, double %p1) {
b0:
  %v3 = call fastcc double @astra.propget.class.0.0(ptr %this)
  %v4 = fmul double %p0, %p1
  %v5 = fadd double %v4, %v3
  ret double %v5
}

define internal fastcc double @astra.propget.class.0.0(ptr %this) {
b0:
  %memory0.field = getelementptr inbounds nuw %astra.class.0, ptr %this, i32 0, i32 0
  %v1 = load double, ptr %memory0.field, align 8
  ret double %v1
}

define internal fastcc void @astra.propset.class.0.0(ptr %this, double %p0) {
b0:
  %memory0.field = getelementptr inbounds nuw %astra.class.0, ptr %this, i32 0, i32 0
  store double %p0, ptr %memory0.field, align 8
  ret void
}

; Function Attrs: cold noreturn nounwind memory(inaccessiblemem: write)
declare void @llvm.trap() #0

attributes #0 = { cold noreturn nounwind memory(inaccessiblemem: write) }
