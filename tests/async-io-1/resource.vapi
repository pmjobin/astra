// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
[CCode (destroy_function = "close_resource")]
handle Resource;
owned Resource open_resource(int value);
int read_resource(borrowed Resource resource);
