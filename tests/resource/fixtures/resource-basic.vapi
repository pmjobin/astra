// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
[CCode(destroy_function = "astra_test_resource_destroy", cheader_filename = "missing/resource.h")]
handle Resource;
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
[CCode(cname = "astra_test_resource_create")] owned Resource create_resource(int id);
[CCode(cname = "astra_test_resource_create_same")] owned Resource create_again(int id);
[CCode(cname = "astra_test_resource_id")] int resource_id(borrowed Resource r);
[CCode(cname = "astra_test_resource_touch")] int resource_touch(borrowed Resource r);
[CCode(cname = "astra_test_resource_raw")] Resource lookup_resource();
[CCode(cname = "astra_test_resource_raw_destroy")] void dispose_raw(Resource r);
[CCode(cname = "astra_test_resource_reset")] void resource_reset();
[CCode(cname = "astra_test_resource_live_count")] int resource_live_count();
[CCode(cname = "astra_test_resource_create_count")] int resource_create_count();
[CCode(cname = "astra_test_resource_destroy_count")] int resource_destroy_count();
[CCode(cname = "astra_test_resource_destroy_order")] int resource_destroy_order();
[CCode(cname = "astra_test_resource_error_count")] int resource_error_count();
[CCode(cname = "astra_test_resource_effect_order")] int resource_effect_order();
[CCode(cname = "astra_test_resource_is_live")] int resource_is_live(borrowed Resource p);
[CCode(cname = "astra_test_resource_touch_count")] int resource_touch_count();
[CCode(cname = "astra_test_resource_null_count")] int resource_null_count();
[CCode(cname = "astra_test_resource_observe3")] int observe3(int first, borrowed Resource p, int last);
