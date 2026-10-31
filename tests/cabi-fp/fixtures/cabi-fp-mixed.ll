; ModuleID = 'astra.scalar'
source_filename = "astra.scalar"

define internal fastcc float @astra.fn.0(float %p0) {
b0:
  ret float %p0
}

define internal fastcc i32 @astra.fn.1() {
b0:
  %v0 = call fastcc float @astra.fn.0(float 1.250000e+00)
  %v1 = fcmp une float %v0, 1.250000e+00
  br i1 %v1, label %b1, label %b2

b1:                                               ; preds = %b0
  ret i32 1

b2:                                               ; preds = %b0
  %v2 = call ptr @c_token()
  %v3 = call double @c_pattern(i32 5)
  %v4 = call double @c_pattern(i32 3)
  %v5 = call i32 @c_mix(i32 7, float %v0, double %v3, ptr %v2, double %v4, i32 9)
  %v6 = icmp ne i32 %v5, 0
  br i1 %v6, label %b3, label %b4

b3:                                               ; preds = %b2
  ret i32 2

b4:                                               ; preds = %b2
  %v7 = call double @c_pattern(i32 0)
  %v8 = call double @c_pattern(i32 1)
  %v9 = call double @c_pattern(i32 2)
  %v10 = call double @c_pattern(i32 3)
  %v11 = call double @c_pattern(i32 4)
  %v12 = call double @c_pattern(i32 5)
  %v13 = call double @c_pattern(i32 6)
  %v14 = call double @c_pattern(i32 7)
  %v15 = call double @c_pattern(i32 8)
  %v16 = call double @c_pattern(i32 9)
  %v17 = call double @c_many(double %v7, double %v8, double %v9, double %v10, double %v11, double %v12, double %v13, double %v14, double %v15, double %v16)
  %v18 = call i32 @c_check(i32 9, double %v17)
  ret i32 %v18
}

declare i32 @c_mix(i32, float, double, ptr, double, i32)

declare double @c_many(double, double, double, double, double, double, double, double, double, double)

declare ptr @c_token()

declare double @c_pattern(i32)

declare i32 @c_check(i32, double)
