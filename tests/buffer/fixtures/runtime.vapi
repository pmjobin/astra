// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
[CCode(destroy_function = "bb_release")]
handle R;
[CCode(cname = "bb_resource")] owned R resource(int id);
[CCode(cname = "bb_id")] int id(borrowed R value);
[CCode(cname = "bb_mark")] int mark(int value);
[CCode(cname = "bb_fail_next")] void fail_next();
[CCode(cname = "bb_pointer")] void* pointer();
[CCode(cname = "bb_f32_zero")] int f32_zero(f32 value);
[CCode(cname = "bb_f64_zero")] int f64_zero(f64 value);
