; ModuleID = 'astra.scalar'
source_filename = "astra.scalar"

define internal fastcc double @astra.fn.0(double %p0) {
b0:
  ret double %p0
}

define internal fastcc double @astra.fn.1(double %p0) {
b0:
  %struct.call = call fastcc double @astra.fn.0(double %p0)
  ret double %struct.call
}

define internal fastcc i32 @astra.fn.2() {
b0:
  %struct.call = call fastcc double @astra.fn.1(double 3.500000e+00)
  %v1 = fcmp une double %struct.call, 3.500000e+00
  br i1 %v1, label %b1, label %b2

b1:                                               ; preds = %b0
  ret i32 1

b2:                                               ; preds = %b0
  ret i32 0
}
