// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#include <stdio.h>
#include <stdlib.h>

struct handle {
	int kind, id;
};
static struct {
	struct handle *pointer;
	int kind, id, dead;
} handles[32];
static struct {
	void *pointer;
	int kind;
} classes[32];
static int count, class_count, releases, destructors, expected_handles, expected_destructors;
static int pointer_checks;

static void require(int condition) {
	if (!condition) {
		fputs("observer violation\n", stderr);
		exit(98);
	}
}
int observe_begin(int resources, int objects) {
	expected_handles = resources;
	expected_destructors = objects;
	return 0;
}
int observe_event(int code, int value) {
	if (code == 'D' || code == 'd') {
		destructors++;
	}
	printf("%c%d\n", code, value);
	return 0;
}
static void *create(int kind, int id) {
	if (id == 0) {
		return NULL;
	}
	require(count < 32);
	struct handle *pointer = malloc(sizeof *pointer);
	require(pointer != NULL);
	pointer->kind = kind;
	pointer->id = id;
	handles[count].pointer = pointer;
	handles[count].kind = kind;
	handles[count].id = id;
	count++;
	printf("A%d:%d\n", kind, id);
	return pointer;
}
void *make_r(int id) {
	return create(1, id);
}
void *make_s(int id) {
	return create(2, id);
}
static int find_handle(void *pointer, int kind) {
	for (int i = 0; i < count; i++) {
		if (handles[i].pointer == pointer && handles[i].kind == kind && !handles[i].dead) {
			return i;
		}
	}
	return -1;
}
int id_r(void *pointer) {
	int index = find_handle(pointer, 1);
	require(index >= 0);
	return handles[index].id;
}
static void destroy(void *pointer, int kind) {
	int index = find_handle(pointer, kind);
	require(index >= 0);
	handles[index].dead = 1;
	releases++;
	printf("X%d:%d\n", kind, handles[index].id);
	free(pointer);
}
void drop_r(void *pointer) {
	destroy(pointer, 1);
}
void drop_s(void *pointer) {
	destroy(pointer, 2);
}
void design_register(void *pointer, int kind) {
	require(class_count < 32);
	classes[class_count].pointer = pointer;
	classes[class_count].kind = kind;
	class_count++;
}
void design_borrow(void *pointer, int kind) {
	pointer_checks++;
	if (pointer == NULL) {
		return;
	}
	if (kind < 10) {
		require(find_handle(pointer, kind) >= 0);
		return;
	}
	for (int i = 0; i < class_count; i++) {
		if (classes[i].pointer == pointer && classes[i].kind == kind) {
			return;
		}
	}
	require(0);
}
int observe_end(void) {
	require(count == expected_handles && releases == expected_handles && destructors == expected_destructors);
	printf("Z%d:%d\n", releases, destructors);
	return 42;
}
#ifdef DESIGN_CLIENT
extern int loan_native_entry(void);
int main(void) {
	int result = loan_native_entry();
	require(result == 42 && pointer_checks > 0);
	printf("P%d\n", pointer_checks);
	return result;
}
#endif
