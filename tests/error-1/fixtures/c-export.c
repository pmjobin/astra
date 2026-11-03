extern int adapter(void);

int foreign_status(void) {
	return 7;
}

int call_adapter(void) {
	return adapter();
}
