// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
[CCode(cname = "astra_test_resource_create", destroy_function = "astra_test_resource_destroy")]
void* create(int id);
[CCode(cname = "astra_test_resource_is_live")]
int inspect(borrowed void* p);
