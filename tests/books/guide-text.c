#include <stdint.h>
#include <stdio.h>

int show_text(const unsigned char *text, int32_t length) {
	if (length < 0 || length > 1024) return 1;
	if (fwrite(text, 1, (size_t)length, stdout) != (size_t)length) return 2;
	return fputc('\n', stdout) == EOF;
}

int check_counted(const unsigned char *text, int32_t length) {
	return length != 3 || text[0] != 0xc3 || text[1] != 0xa9 || text[2] != 0;
}
