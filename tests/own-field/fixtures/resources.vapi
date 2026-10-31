// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
[CCode(destroy_function = "of_release")]
handle R;
[CCode(destroy_function = "of_release_other")]
handle Other;
[CCode(cname = "of_make")] owned R make(int id);
[CCode(cname = "of_make_other")] owned Other make_other(int id);
[CCode(cname = "of_id")] int id(borrowed R value);
[CCode(cname = "of_other_id")] int other_id(borrowed Other value);
[CCode(cname = "of_live")] int live();
[CCode(cname = "of_mark")] int mark(int code);
