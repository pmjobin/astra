[CCode (cname = "c_echo", cheader_filename = "cabi-fp.h")]
double echo_double(double value);
double c_produce();
void c_consume(double value);
int c_consumed(int index);
double c_pattern(int index);
int c_count();
int c_check(int index, double value);
[CCode (cname = "c_echo32", cheader_filename = "cabi-fp.h")]
float echo_float(float value);
float c_produce32();
void c_consume32(float value);
int c_consumed32(int index);
float c_pattern32(int index);
int c_count32();
int c_check32(int index, float value);
