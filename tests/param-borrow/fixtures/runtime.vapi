// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
[CCode(destroy_function = "bb_release")] handle R;
[CCode(cname = "bb_resource")] owned R resource(int id);
[CCode(cname = "bb_id")] int id(borrowed R value);
[CCode(cname = "bb_mark")] int mark(int value);
[CCode(cname = "pb_touch")] int touch(borrowed R value);
[CCode(cname = "pb_value")] int value(borrowed R value);
