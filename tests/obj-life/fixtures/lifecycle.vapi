// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
[CCode(destroy_function = "life_destroy")]
handle Resource;
[CCode(cname = "life_create")] owned Resource create_resource(int id);
[CCode(cname = "life_id")] int resource_id(borrowed Resource r);
[CCode(cname = "life_live")] int resource_live();
