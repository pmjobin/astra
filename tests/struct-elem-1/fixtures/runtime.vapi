// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
[CCode(destroy_function = "se_drop")]
handle R;
[CCode(cname = "se_resource")] owned R resource(int id);
