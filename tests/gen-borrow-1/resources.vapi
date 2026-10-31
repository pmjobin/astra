// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
[CCode(destroy_function = "drop_r")] handle R;
[CCode(destroy_function = "drop_s")] handle S;
[CCode(cname = "make_r")] owned R create_r(int id);
[CCode(cname = "make_s")] owned S create_s(int id);
[CCode(cname = "id_r")] int resource_id(borrowed R value);
