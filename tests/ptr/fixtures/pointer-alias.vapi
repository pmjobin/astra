[CCode (cname = "astra_test_handle_a", cheader_filename = "nonexistent/pointer_api.h")]
void* handle_a();
[CCode (cname = "astra_test_handle_b")]
void* handle_b();
[CCode (cname = "astra_test_null")]
void* null_handle();
[CCode (cname = "astra_test_is_handle_a")]
int is_handle_a(void* p);
[CCode (cname = "astra_test_is_handle_b")]
int is_handle_b(void* p);
[CCode (cname = "astra_test_is_null")]
int is_null(void* p);
[CCode (cname = "astra_test_guarded_handle_a")]
int guarded_handle_a(void* p);
[CCode (cname = "astra_test_predicate_calls")]
int predicate_calls();
