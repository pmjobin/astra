# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Independent NATIVEABI-13 inputs and expectations, frozen before lowering."""

CASES = {
	'fp32-call': ('fp', 'f32 twice(f32 x){return x+x;}int main(){f32 x=1.25f;if(twice(x)!=2.5f){return 1;}return 0;}'),
	'fp64-branch': ('fp', 'f64 adjust(f64 x){if(x<0.0d){return -x;}return x/2.0d;}int main(){if(adjust(-3.5d)!=3.5d||adjust(7.0d)!=3.5d){return 1;}return 0;}'),
	'fp-width-casts': ('fp', 'f64 wide(f32 x){return x as f64;}f32 narrow(f64 x){return x as f32;}int main(){if(wide(1.5f)!=1.5d||narrow(1.000000059604644775390625d)!=1.0f){return 1;}return 0;}'),
	'fp-unordered': ('fp', 'f64 divide(f64 x,f64 y){return x/y;}bool equal(f64 x,f64 y){return x==y;}bool different(f64 x,f64 y){return x!=y;}int main(){f64 x=divide(0.0d,0.0d);if(equal(x,x)||!different(x,x)){return 1;}return 0;}'),
	'c-import-i32': ('c', 'extern(C) int c_mix(int a,int b);int main(){if(c_mix(-7,19)!=43){return 1;}return 0;}'),
	'c-import-fp': ('c', 'extern(C) f32 c_float(f32 x);extern(C) f64 c_double(f64 x);int main(){if(c_float(1.25f)!=2.5f||c_double(-3.5d)!=-1.75d){return 1;}return 0;}'),
	'c-export-fp': ('c', 'f64 identity(f64 x){return x;}export(C) f32 astra_float(f32 x){return x;}export(C) f64 astra_double(f64 x){return identity(x);}'),
	'c-mixed-pointer': ('c', 'extern(C) int c_channels(int tag,f32 small,f64 precise,void* token);export(C) void* astra_pointer(void* token){return token;}export(C) int astra_channels(int tag,f32 small,f64 precise,void* token){return c_channels(tag,small,precise,token);}'),
	'aggregate-nested-fp': ('memory', 'struct Inner{f64 value;int tag;}struct Outer{int head;Inner inner;f32 tail;}f64 sum(Outer value){return value.inner.value+value.tail as f64;}int main(){Outer value={head=7,inner={value=1.25d,tag=9},tail=2.5f};if(sum(value)!=3.75d||value.inner.tag!=9){return 1;}return 0;}'),
	'aggregate-borrow-fp': ('memory', 'struct Pair{f32 small;f64 precise;}f64 read(borrowed Pair value){return value.precise;}int main(){Pair value={small=1.5f,precise=2.25d};Pair copy=value;copy.precise=3.5d;if(read(value)!=2.25d||read(copy)!=3.5d){return 1;}return 0;}'),
	'owner-buffer-replace': ('memory', 'int main(){owned int[] value=new int[2];value=new int[3];return 0;}'),
	'owner-branch-replace': ('memory', 'int main(){owned int[] value=new int[2];int i=0;while(i<3){if(i==1){value=new int[4];}else{value=new int[3];}i=i+1;}return 0;}'),
}

# Requested element counts; the runner multiplies by the checked int size.
TRACES = {
	'owner-buffer-replace': [('A', 2), ('A', 3), ('F', 2), ('F', 3)],
	'owner-branch-replace': [('A', 2), ('A', 3), ('F', 2), ('A', 4), ('F', 3), ('A', 3), ('F', 4), ('F', 3)],
}

C_WITNESSES = {
	'c-import-i32': '#include <stdint.h>\nint32_t c_mix(int32_t a,int32_t b){return a*2+b*3;}\n',
	'c-import-fp': 'float c_float(float x){return x*2.0f;}\ndouble c_double(double x){return x/2.0;}\n',
	'c-export-fp': '''#include <stdint.h>
#include <string.h>
extern float astra_float(float);
extern double astra_double(double);
int main(void){
	const uint32_t small[]={0,0x80000000u,1,0x7f800000u,0x7fc01234u,0x7f7fffffu};
	const uint64_t precise[]={0,UINT64_C(0x8000000000000000),1,UINT64_C(0x7ff0000000000000),UINT64_C(0x7ff8000000001234),UINT64_C(0x7fefffffffffffff)};
	for(unsigned i=0;i<sizeof small/sizeof *small;i++){float x,y;uint32_t bits;memcpy(&x,&small[i],sizeof x);y=astra_float(x);memcpy(&bits,&y,sizeof bits);if(bits!=small[i])return 1;}
	for(unsigned i=0;i<sizeof precise/sizeof *precise;i++){double x,y;uint64_t bits;memcpy(&x,&precise[i],sizeof x);y=astra_double(x);memcpy(&bits,&y,sizeof bits);if(bits!=precise[i])return 2;}
	return 0;
}
''',
	'c-mixed-pointer': '''#include <stdint.h>
#include <string.h>
static int storage;
extern void *astra_pointer(void *);
extern int32_t astra_channels(int32_t,float,double,void *);
int32_t c_channels(int32_t tag,float small,double precise,void *token){return tag==-7&&small==1.25f&&precise==-3.5&&token==&storage?0:1;}
int main(void){if(astra_pointer(&storage)!=&storage||astra_pointer(0)!=0)return 2;return astra_channels(-7,1.25f,-3.5,&storage);}
''',
}
