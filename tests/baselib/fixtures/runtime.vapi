[CCode(destroy_function = "test_release")] handle Resource;
[CCode(cname = "test_acquire")] owned Resource acquire(int id);
