// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
[CCode(destroy_function = "property_resource_drop")] handle PropertyResource;
[CCode(cname = "property_resource_make")] owned PropertyResource make_resource(int value);
[CCode(cname = "property_resource_value")] int resource_value(borrowed PropertyResource resource);
