// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
[CCode(destroy_function = "bb_release")] handle Resource;
[CCode(cname = "bb_resource")] owned Resource resource(int id);
[CCode(cname = "bb_id")] int id(borrowed Resource value);
[CCode(cname = "bb_mark")] int mark(int value);
[CCode(cname = "bb_pointer")] void* pointer();
[CCode(cname = "inf_vapi_double")] double foreign_double();
[CCode(cname = "inf_float")] float foreign_float();
[CCode(cname = "inf_bits64")] int bits64(double value, int high, int low);
[CCode(cname = "inf_bits32")] int bits32(float value, int expected);
[CCode(destroy_function = "bb_release")] handle Token;
[CCode(cname = "gi_token")] owned Token token(int id);
