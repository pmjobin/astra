// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
[CCode(cname = "allocation_example_failure")]
void application_failure(int code, int count);
[CCode(cname = "allocation_example_report", text_abi = "utf8-i32")]
void application_report(int count, borrowed string file, int line, borrowed string expression);
