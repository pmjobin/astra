// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
[CCode(destroy_function = "nonnull_release")]
handle R;
[CCode(cname = "nonnull_acquire")] owned R acquire(int value);
[CCode(cname = "nonnull_id")] int id(borrowed R value);
[CCode(cname = "nonnull_live")] int live();
