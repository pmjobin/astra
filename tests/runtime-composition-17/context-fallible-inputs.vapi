// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
[CCode(destroy_function = "admission_token_close")]
handle AdmissionToken;
owned AdmissionToken admission_token(int id);
int admission_token_identity(borrowed AdmissionToken token);
