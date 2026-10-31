// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
[CCode(cname = "astra_test_resource_is_live")] int resource_is_live(borrowed void* p);
[CCode(cname = "astra_test_resource_id")] int resource_id(borrowed void* p);
[CCode(cname = "astra_test_resource_touch", cheader_filename = "missing/borrowed.h")] int resource_touch(borrowed void* p);
[CCode(cname = "astra_test_resource_touch_count")] int resource_touch_count();
[CCode(cname = "astra_test_resource_null_count")] int resource_null_count();
[CCode(cname = "astra_test_resource_raw")] void* resource_raw();
[CCode(cname = "astra_test_resource_raw_destroy")] void resource_raw_destroy(void* p);
[CCode(cname = "astra_test_resource_observe3")] int observe3(int first, borrowed void* p, int last);
