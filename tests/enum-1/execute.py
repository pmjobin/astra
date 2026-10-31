# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Actual Astra execution and exact scalar/vector transport observers."""
from pathlib import Path
import json
import os
import re
import subprocess
import sys

sys.dont_write_bytecode = True

def run(argv, status=0):
	p = subprocess.run(list(map(str,argv)),capture_output=True,text=True,env=dict(os.environ,CCACHE_DISABLE='1'))
	assert p.returncode == status and not p.stderr, (argv,p)
	return p.stdout

RUNTIME = '''
struct Header { int version; int size; }
struct Counter { int value; }
enum DecodeError { BadMagic, Version(int actual), Short(int count), }
enum HeaderResult { Ready(Header header), Failed(DecodeError error), }
enum Colour { Red, Green, Blue, }
int effect(Counter* counter,int value){counter->value=counter->value*10+value;return value;}
HeaderResult decode(int magic,int version,int size){
	if(magic!=42){return HeaderResult.Failed(DecodeError.BadMagic());}
	if(version!=7){return HeaderResult.Failed(DecodeError.Version(version));}
	if(size<4){return HeaderResult.Failed(DecodeError.Short(size));}
	Header header={version=version,size=size};return HeaderResult.Ready(header);
}
int policy(HeaderResult result){
	match(result){
		case HeaderResult.Ready(header):{return header.version*10+header.size;}
		case HeaderResult.Failed(error):{match(error){
			case DecodeError.BadMagic():{return 1;}
			case DecodeError.Version(actual):{return actual+2;}
			case DecodeError.Short(count):{return count+3;}
		}}
	}
}
HeaderResult recursive(int count){if(count==0){return decode(42,7,4);}return recursive(count-1);}
enum Triple{Small(int value),Large(int left,int middle,int right)}
int sum(Triple value){match(value){case Triple.Small(v):{return v;}case Triple.Large(right=r,left=l,middle=m):{return l*100+m*10+r;}}}
int change(Header* header){header->version=99;header->size=99;return 0;}
int captured(HeaderResult value,int effect){return policy(value)+effect;}
int cleanup(Triple value){owned int[] data=new int[2];data[0]=1;int n=0;while(n<3){n=n+1;match(value){case Triple.Small(_):{if(n<3){continue;}break;}else:{data[1]=n;}}}return data[0]+n;}
int main(){
	if(policy(decode(1,7,4))!=1){return 1;}
	if(policy(decode(42,5,4))!=7){return 2;}
	if(policy(decode(42,7,2))!=5){return 3;}
	if(policy(recursive(17))!=74){return 4;}
	Counter counter={value=0};var triple=Triple.Large(effect(&counter,1),effect(&counter,2),effect(&counter,3));
	if(counter.value!=123||sum(triple)!=123){return 5;}
	var copy=triple;triple=Triple.Small(9);if(sum(copy)!=123||sum(triple)!=9){return 6;}
	triple=copy;copy=Triple.Small(2);if(sum(triple)!=123){return 7;}
	Header header={version=7,size=4};if(captured(HeaderResult.Ready(header),change(&header))!=74||header.version!=99){return 8;}
	if(Colour.Red()==Colour.Blue()||Colour.Green()!=Colour.Green()){return 9;}
	if(cleanup(Triple.Small(3))!=4||cleanup(Triple.Large(1,2,3))!=4){return 10;}
	return 0;
}
'''

def depth_program(depth):
	lines = ['enum E0{Value(int value)}','int read0(E0 x){match(x){case E0.Value(v):{return v;}}}']
	value = 'E0.Value(13)'
	for i in range(1,depth):
		lines += [f'enum E{i}{{Value(E{i-1} value)}}',f'int read{i}(E{i} x){{match(x){{case E{i}.Value(v):{{return read{i-1}(v);}}}}}}']
		value = f'E{i}.Value({value})'
	lines += [f'int main(){{return read{depth-1}({value})-13;}}']
	return '\n'.join(lines)

def transport_matrix(compiler,out):
	channels=[]
	for name,width,llvm in [('i8',8,'i8'),('u8',8,'i8'),('i16',16,'i16'),('u16',16,'i16'),('int',32,'i32'),('u32',32,'i32'),('f32',32,'float'),('f64',64,'double'),('bool',1,'i1'),('void*',64,'ptr')]:
		channels.append((name,width,llvm,1))
	for name,width,llvm in [('i8',8,'i8'),('u8',8,'i8'),('i16',16,'i16'),('u16',16,'i16'),('int',32,'i32'),('u32',32,'i32'),('f32',32,'float'),('bool',1,'i1')]:
		for lanes in (2,4,8,16):
			if name!='bool' and width*lanes>128:continue
			channels.append((f'{name}<{lanes}>',width,f'<{lanes} x {llvm}>',lanes))
	code=[]
	for i,(name,width,llvm,lanes) in enumerate(channels):
		code += [f'enum Payload{i}{{Value({name} value)}}',f'Payload{i} put{i}({name} x){{return Payload{i}.Value(x);}}',f'{name} get{i}(Payload{i} x){{match(x){{case Payload{i}.Value(v):{{return v;}}}}}}']
	path=out/'transport.astra';path.write_text('\n'.join(code)+'\n')
	ir=run([compiler,'--dump-llvm',path])
	assert not re.search(r'@(malloc|calloc|realloc|free)\(',ir) and 'llvm.memcpy' in ir
	ir=re.sub(r'^define internal fastcc ([^\n]+) \{$',r'define fastcc \1 noinline {',ir,flags=re.M)
	lines=[ir,'define i32 @main(){','entry:']; previous='true';checks=0
	for i,(name,width,llvm,lanes) in enumerate(channels):
		if 'float' in llvm:
			selected=[0,1,0x007fffff,0x00800000,0x3f800000,0x7f800000,0x7fc12345,0x80000000,0x80000001,0xff800000,0xffc12345]
		elif llvm=='double':
			selected=[0,1,0x000fffffffffffff,0x0010000000000000,0x3ff0000000000000,0x7ff0000000000000,0x7ff8123456789abc,0x8000000000000000,0x8000000000000001,0xfff0000000000000,0xfff8123456789abc]
		else:selected=[0,1,(1<<width)-1,1<<(width-1)]
		for pattern in selected:
			index=checks;checks+=1
			lane_bits=[(pattern if lane%2==0 else selected[(selected.index(pattern)+1)%len(selected)]) for lane in range(lanes)]
			bits=sum(value<<(width*lane) for lane,value in enumerate(lane_bits))
			physical='i'+str(width*lanes)
			if llvm=='ptr':argument=f'inttoptr (i64 {bits} to ptr)'
			elif lanes>1 or llvm in ('float','double'):argument=f'bitcast ({physical} {bits} to {llvm})'
			else:argument=str(bits)
			lines += [f'\t%s{index}=alloca [64 x i8],align 16',f'\tcall fastcc void @astra.fn.{i*2}(ptr %s{index},{llvm} {argument})',f'\t%r{index}=call fastcc {llvm} @astra.fn.{i*2+1}(ptr %s{index})']
			if llvm=='ptr':lines += [f'\t%b{index}=ptrtoint ptr %r{index} to i64']
			elif lanes>1 or llvm in ('float','double'):lines += [f'\t%b{index}=bitcast {llvm} %r{index} to {physical}']
			else:lines += [f'\t%b{index}=add {physical} %r{index},0']
			lines += [f'\t%ok{index}=icmp eq {physical} %b{index},{bits}',f'\t%pass{index}=and i1 {previous},%ok{index}'];previous=f'%pass{index}'
	lines += [f'\t%success=select i1 {previous},i32 0,i32 1','\tret i32 %success','}']
	path=out/'transport.ll';path.write_text('\n'.join(lines)+'\n')
	for mode in ('O0','O2','O2-fma'):
		final=out/('transport-'+mode+'.ll')
		if mode!='O0':run(['opt','-passes=default<O2>','-S',path,'-o',final])
		else:final.write_text(path.read_text())
		run(['opt','-passes=verify','-disable-output',final]);obj=final.with_suffix('.o');exe=out/('transport-'+mode)
		run(['llc','-O0' if mode=='O0' else '-O2','-filetype=obj','-relocation-model=pic',*(['-mattr=+fma'] if mode=='O2-fma' else []),final,'-o',obj]);run(['cc',obj,'-o',exe]);run([exe])
	return dict(scalar_channels=10,vector_mask_shapes=len(channels)-10,exact_bit_checks=checks,modes=['O0','preserved-O2','preserved-O2-fma'])

def main(compiler,out):
	out.mkdir(parents=True,exist_ok=True)
	for name,code in [('runtime',RUNTIME),('depth-64',depth_program(64))]:
		path=out/(name+'.astra');path.write_text(code+'\n');exe=out/name
		run([compiler,path,'-o',exe]);assert run([exe])==''
		if name == 'runtime':
			ir = run([compiler,'--dump-llvm',path]); ordinal = re.search(r'\(function #(\d+) "main" -> int',run([compiler,'--dump-ssa',path]))[1]; ir += '\ndefine i32 @main(){\n\t%r=call fastcc i32 @astra.fn.'+ordinal+'()\n\tret i32 %r\n}\n'
			for mode in ('O0','O2','O2-fma','preserved-O2'):
				input_ir = re.sub(r'^define internal fastcc ([^\n]+) \{$',r'define fastcc \1 noinline {',ir,flags=re.M) if mode=='preserved-O2' else ir
				inp=out/(name+'-'+mode+'-input.ll');final=out/(name+'-'+mode+'.ll');inp.write_text(input_ir)
				if mode=='O0':final.write_text(input_ir)
				else:run(['opt','-passes=default<O2>','-S',inp,'-o',final])
				obj=final.with_suffix('.o');binary=out/(name+'-'+mode)
				run(['llc','-O0' if mode=='O0' else '-O2','-filetype=obj','-relocation-model=pic',*(['-mattr=+fma'] if mode=='O2-fma' else []),final,'-o',obj]);run(['cc',obj,'-o',binary]);assert run([binary])==''
				if mode=='preserved-O2':assert 'call fastcc' in final.read_text()
	results=transport_matrix(compiler,out);results['runtime_programs']=2;results['runtime_modes']=['normal','O0','O2','O2-fma','preserved-O2']
	(out/'results.json').write_text(json.dumps(results,indent=2)+'\n');print(json.dumps(results))

if __name__=='__main__':
	main(*(Path(arg).resolve() for arg in sys.argv[1:]))
