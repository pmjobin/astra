/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
static int constructed[7], destroyed[7], retired[7], tokens[7];

void *admission_token(int id) {
	assert(id > 0 && id < 6 && tokens[id] == 0);
	int *token = malloc(sizeof(*token));
	assert(token);
	*token = id;
	tokens[id] = 1;
	return token;
}

int admission_token_identity(const void *value) {
	const int *token = value;
	assert(token && *token > 0 && *token < 6 && tokens[*token] == 1);
	return *token;
}

void admission_token_close(void *value) {
	if (!value) {
		return;
	}
	int *token = value;
	assert(*token > 0 && *token < 6 && tokens[*token] == 1);
	tokens[*token] = 2;
	free(token);
}

int admission_event(int kind, int id) {
	assert(id > 0 && id < 7);
	if (kind == 1) {
		assert(constructed[id]++ == 0);
	} else if (kind == 2) {
		assert(destroyed[id]++ == 0);
	} else {
		assert(kind == 3 && id <= 2 && retired[id]++ == 0 && destroyed[id] == 0);
	}
	return 0;
}

int admission_finish(void) {
	for (int id = 1; id < 6; ++id) {
		assert(constructed[id] == 1 && destroyed[id] == 1 && tokens[id] == 2 && retired[id] == (id <= 2));
	}
	assert(constructed[6] == 0 && destroyed[6] == 1 && retired[6] == 0 && tokens[6] == 0);
	puts("fallible inputs: refusal preserves caller owners, admission empties slots and rollback retires each input once");
	return 0;
}
