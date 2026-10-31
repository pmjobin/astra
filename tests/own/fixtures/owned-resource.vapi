// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
[CCode(cname = "astra_test_resource_create", cheader_filename = "opaque/resource.h", destroy_function = "astra_test_resource_destroy")]
void* create_resource(int id);
[CCode(cname = "astra_test_resource_reset")] void resource_reset();
[CCode(cname = "astra_test_resource_live_count")] int resource_live_count();
[CCode(cname = "astra_test_resource_create_count")] int resource_create_count();
[CCode(cname = "astra_test_resource_destroy_count")] int resource_destroy_count();
[CCode(cname = "astra_test_resource_destroy_order")] int resource_destroy_order();
[CCode(cname = "astra_test_resource_error_count")] int resource_error_count();
[CCode(cname = "astra_test_resource_record_effect")] int record_effect(int id);
[CCode(cname = "astra_test_resource_effect_order")] int resource_effect_order();
[CCode(cname = "astra_test_resource_forbid_cleanup")] void resource_forbid_cleanup();
