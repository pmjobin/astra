/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
/* Select an already built compiler image before any LLVM library is loaded.
 * Both images use the same native Astra object and argv transport. */
#define _POSIX_C_SOURCE 200809L
#include <stdio.h>
#include <string.h>
#include <unistd.h>

int main(int argc, char **argv) {
	char image[4096];
	ssize_t length = readlink("/proc/self/exe",image,sizeof(image)-16);
	if (length < 1 || (size_t)length >= sizeof(image) - 16) {
		fputs("astrac: cannot resolve compiler image\n",stderr);
		return 127;
	}
	image[length] = 0;
	strcat(image,argc > 1 && strcmp(argv[1],"doc") == 0 ? ".doc" : ".native");
	execv(image,argv);
	fputs("astrac: paired compiler image unavailable\n",stderr);
	return 127;
}
