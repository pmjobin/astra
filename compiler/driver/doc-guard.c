/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
/* The semantic-only image has no LLVM dependency. Every backend import is
 * bound to this fatal guard: an accidental backend call can never succeed. */
#define _POSIX_C_SOURCE 200809L
#include <stdlib.h>
#include <unistd.h>

_Noreturn void astrac_doc_backend_unavailable(void) {
	static const char message[] = "astrac doc: forbidden LLVM backend call\n";
	(void)write(STDERR_FILENO,message,sizeof(message)-1);
	_Exit(127);
}
