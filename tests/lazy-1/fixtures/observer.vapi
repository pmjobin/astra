// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
[CCode(destroy_function = "lazy_destroy")]
handle Resource;
[CCode(cname = "lazy_create")] owned Resource create_resource(int code);
[CCode(cname = "lazy_live")] int resource_live();
