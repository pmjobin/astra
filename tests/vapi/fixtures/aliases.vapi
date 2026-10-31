// Local callable names differ from physical C symbols.
[CCode (cname = "astra_test_add_impl")]
int add(int a, int b);
[CCode (cname = "astra_test_identity")]
int echo(int value);
[CCode (
	cname = "astra_test_reset_impl",
	cheader_filename = "helper/test_api.h"
)]
void reset();
