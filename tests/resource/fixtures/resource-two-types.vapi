// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
[CCode(destroy_function = "astra_test_resource_destroy")] handle ResourceA;
[CCode(destroy_function = "astra_test_resource_destroy")] handle ResourceB;
[CCode(destroy_function = "astra_test_resource_destroy_other")] handle Device;
[CCode(cname = "astra_test_resource_create_a")] owned ResourceA create_a(int id);
[CCode(cname = "astra_test_resource_create_b")] owned ResourceB create_b(int id);
[CCode(cname = "astra_test_resource_create_other")] owned Device create_device(int id);
