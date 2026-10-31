# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Strict GIR checked-out profile -> declaration-driven GObject imports.

This module consumes the bounded XML parser in import.py. It emits declarations
and provenance, never native implementation bodies or per-application adapters.
"""
import hashlib
import json
import re
import subprocess
from pathlib import Path

GI='http://www.gtk.org/introspection/core/1.0}'
C='http://www.gtk.org/introspection/c/1.0}'
GLIB='http://www.gtk.org/introspection/glib/1.0}'
IDENT=re.compile(r'[A-Za-z_][A-Za-z0-9_]*\Z')
SCALARS={'gint':('int','gint'),'guint':('u32','guint'),'gint64':('i64','gint64'),'guint64':('u64','guint64'),'gfloat':('f32','gfloat'),'gdouble':('f64','gdouble'),'gboolean':('bool','gboolean'),'none':('void','void')}


def generate(profile, profile_bytes, documents, entry_bytes, Rejected):
	def require(condition,message):
		if not condition:raise Rejected(message)
	def ident(value):require(isinstance(value,str) and IDENT.fullmatch(value),'invalid declaration identifier '+str(value));return value
	def exact(value,keys):require(isinstance(value,dict) and set(value)==set(keys),'unknown/missing declarations profile fact')
	def attrs(node):
		result={}
		for child in node.children:
			if child.tag!=GI+'attribute':continue
			child.attrs({'name','value'});child.content(set());key=child.attributes.get('name');value=child.attributes.get('value');require(key in {'astra.profile','astra.kind','astra.encoding','astra.direction','astra.produced','astra.error-domain','astra.error-codes','astra.native-type','astra.signal-scope','astra.signal-closure','astra.signal-destroy'},'unsupported GIR semantic attribute');require(key not in result and isinstance(value,str),'duplicate/missing GIR attribute');result[key]=value
		return result
	def children(node,tag):return [c for c in node.children if c.tag==GI+tag]
	def parameter_list(node,signal=False):
		# GIR permits an absent parameter group for zero-argument callables.
		# Method receiver and callback userdata requirements remain explicit.
		if not children(node,'parameters'):return [],[]
		group=node.one(GI+'parameters');group.attrs(set());group.content({GI+'parameter'} if signal else {GI+'parameter',GI+'instance-parameter'})
		return children(group,'parameter'),children(group,'instance-parameter')
	def only(node,tag,name):
		found=[c for c in children(node,tag) if c.attributes.get('name')==name];require(len(found)==1,'missing/duplicate selected '+tag+' '+str(name));return found[0]
	def named(namespace,name):return name if '.' in name else namespace+'.'+name
	def nullable(node):
		value=node.attributes.get('nullable',node.attributes.get('allow-none','0'));require(value in ('0','1') and node.attributes.get('allow-none',value)==value,'invalid/conflicting nullable fact');return value=='1'
	def transfer(node):
		value=node.attributes.get('transfer-ownership');require(value in ('none','full'),'explicit transfer none/full required');return value
	def typed(node):
		found=children(node,'type');require(len(found)==1 and not children(node,'array'),'exact scalar/object/boxed GIR type required');t=found[0];t.attrs({'name',C+'type'});t.content(set());return t.attributes.get('name'),t.attributes.get(C+'type')
	require(len(profile_bytes)<=16*1024*1024,'declarations GIR profile exceeds finite limit')
	exact(profile,('format','target','namespaces','packages','objects','error'))
	require(profile['target']=='gnu-x86_64-sysv-lp64','unsupported declarations GIR target')
	exact(profile['error'],('type','factory','domain','cases'));error=profile['error'];ident(error['type']);ident(error['factory']);require(type(error['domain']) is int and 0<error['domain']<2**31,'invalid error domain');require(isinstance(error['cases'],dict) and 0<len(error['cases'])<=1024,'invalid error cases')
	for origin,code in error['cases'].items():ident(origin);require(type(code)is int and -2**31<=code<0,'invalid checked error status')
	require(len(set(error['cases'].values()))==len(error['cases']),'duplicate checked error status')
	spaces={};inputs={}
	for root,digest in documents:
		node=root.one(GI+'namespace');name=ident(node.attributes.get('name'));require(name not in spaces and profile['namespaces'].get(name)==node.attributes.get('version'),'namespace/version mismatch');spaces[name]=node;inputs[name]=digest
	require(set(spaces)==set(profile['namespaces']),'missing selected namespace')
	objects={};sources=set();prefixes=set()
	require(isinstance(profile['objects'],list) and 0<len(profile['objects'])<=1024,'invalid object inventory')
	for selected in profile['objects']:
		exact(selected,('namespace','name','source','prefix','header','ctype','get_type','parent','constructors','methods','properties','signals'));ns=ident(selected['namespace']);name=ident(selected['name']);source=ident(selected['source']);prefix=ident(selected['prefix']);key=ns+'.'+name
		require(ns in spaces and key not in objects and source not in sources and prefix not in prefixes,'duplicate/missing object identity');sources.add(source);prefixes.add(prefix)
		header=selected['header'];require(isinstance(header,str) and re.fullmatch(r'[A-Za-z0-9_./-]+\.h',header) and not header.startswith('/') and '..' not in header,'unsafe SDK header')
		node=only(spaces[ns],'class',name);require(node.attributes.get('abstract','0')=='0' and node.attributes.get('introspectable','1')=='1','abstract/non-introspectable class');node.attrs({'name',C+'type',C+'symbol-prefix',GLIB+'type-name',GLIB+'get-type',GLIB+'type-struct','parent','abstract','final','version','introspectable'});ctype=ident(node.attributes.get(C+'type'));get_type=ident(node.attributes.get(GLIB+'get-type'));require(get_type.endswith('_get_type'),'explicit get_type required');require(ctype==selected['ctype'] and get_type==selected['get_type'] and node.attributes.get('parent')==selected['parent'],'SDK C/GType/parent differs from selected profile');symbol=get_type[:-9]
		for category in ('constructors','methods','properties','signals'):
			values=selected[category];require(isinstance(values,list) and len(values)<=4096 and len(set(values))==len(values),'invalid selected members');[require(isinstance(v,str) and re.fullmatch(r'[A-Za-z_][A-Za-z0-9_-]*',v),'invalid member selection') for v in values]
		objects[key]=dict(selected,node=node,ctype=ctype,symbol=symbol)
	records={};callbacks={};contract=[];signal_bindings=[]
	def record(key):
		if key in records:return records[key]
		ns,name=key.split('.',1);node=only(spaces[ns],'record',name);ctype=ident(node.attributes.get(C+'type'));get_type=ident(node.attributes.get(GLIB+'get-type'));require(get_type.endswith('_get_type'),'boxed record lacks get_type');prefix=get_type[:-9]
		require(only(node,'method','free').attributes.get(C+'identifier')==prefix+'_free','boxed free identity mismatch');require(only(node,'method','copy').attributes.get(C+'identifier')==prefix+'_copy','boxed copy identity mismatch')
		source=ident('Gir'+ns+name);require(source not in sources,'record/source collision');sources.add(source);fields=[]
		for index,field in enumerate(children(node,'field')):
			field.attrs({'name','writable','readable','private'});require(field.attributes.get('private','0')=='0','private boxed field');fname=field.attributes.get('name');match=re.fullmatch(r'astra_field_(\d+)_([A-Za-z_][A-Za-z0-9_]*)',fname or '');require(match and int(match[1])==index,'boxed field ordinal/member identity mismatch');kind,c=typed(field);require(kind in SCALARS and kind!='none' and c==SCALARS[kind][1],'boxed field scalar ABI mismatch');fields.append((ident(match[2]),SCALARS[kind][0]))
		require(0<len(fields)<=1024 and len({f[0] for f in fields})==len(fields),'invalid boxed field inventory');result=dict(source=source,ctype=ctype,prefix=prefix,fields=fields,attributes=attrs(node));records[key]=result;return result
	def callback(key):
		if key in callbacks:return callbacks[key]
		ns,name=key.split('.',1);node=only(spaces[ns],'callback',name);require(node.attributes.get('throws','0')=='0','throwing callback');ret=node.one(GI+'return-value');kind,c=typed(ret);require(kind in SCALARS and c==SCALARS[kind][1] and transfer(ret)=='none','callback return ABI');args=children(node.one(GI+'parameters'),'parameter');require(args and len(args)<=257,'callback parameter bound');kind0,c0=typed(args[0]);require(kind0=='gpointer' and c0=='gpointer' and args[0].attributes.get('closure')=='0' and transfer(args[0])=='none','callback requires explicit leading userdata');types=[]
		for arg in args[1:]:
			k,c=typed(arg);require(k in SCALARS and k!='none' and c==SCALARS[k][1] and transfer(arg)=='none' and not nullable(arg),'callback copied scalar ABI');types.append(SCALARS[k][0])
		result='Callback<'+','.join([SCALARS[kind][0],*types])+'>';callbacks[key]=result;return result
	def channel(node,ns,out=False):
		node.attrs({'name','transfer-ownership','nullable','allow-none','direction','caller-allocates','scope','closure','destroy'});node.content({GI+'type',GI+'attribute'});meta=attrs(node);kind,c=typed(node);ownership=transfer(node);nil=nullable(node);direction=node.attributes.get('direction','in');annotation=[]
		if kind in SCALARS:
			require(not nil and c==SCALARS[kind][1]+('*' if out or direction in ('out','inout') else ''),'scalar C ABI/direction mismatch');require(out or direction in ('out','inout') or ownership=='none','copied scalar transfer mismatch');return dict(source=SCALARS[kind][0],kind='scalar',meta=meta,nullable=False,direction=direction)
		key=named(ns,kind)
		if key in objects:
			obj=objects[key];require(c==obj['ctype']+('**' if out else '*'),'object nominal C ABI mismatch');require(not out or ownership=='full','owned object output required');return dict(source=('owned ' if out or ownership=='full' else 'borrowed ')+obj['source'],kind='object',meta=meta,nullable=nil,direction=direction)
		if kind=='GLib.Bytes' or kind=='utf8':
			require(meta.get('astra.kind') in ('bytes','text') and meta.get('astra.encoding') in ('bytes','utf8-counted','utf8-nul'),'missing exact byte/text encoding');encoding=meta['astra.encoding'];require((kind=='utf8')==(encoding=='utf8-nul') and c==('gchar' if kind=='utf8' else 'GBytes')+('**' if out else '*'),'byte/text physical encoding mismatch');require(ownership==('full' if out else 'none'),'byte/text transfer mismatch');source='owned u8[]' if out else 'string' if meta['astra.kind']=='text' else 'borrowed u8[]';return dict(source=source,kind=meta['astra.kind'],meta=meta,nullable=nil,direction=direction)
		found=[n for n in spaces[ns].children if n.tag==GI+'callback' and n.attributes.get('name')==kind]
		if found:
			require(not out and ownership=='none' and node.attributes.get('scope')=='call' and 'destroy' not in node.attributes,'callback scope/retention mismatch');require(c==found[0].attributes.get(C+'type'),'callback C type mismatch');return dict(source='borrowed '+callback(key),kind='callback',meta=meta,nullable=nil,direction=direction)
		boxed=record(key);require(c==boxed['ctype']+('**' if out else '*') and ownership==('full' if out else 'none') and not nil,'boxed direction/ownership ABI mismatch');return dict(source=boxed['source'],kind='record',record=key,meta=meta,nullable=False,direction=direction)
	def checked(member):
		member.attrs({'name',C+'identifier','throws','version','introspectable','deprecated','deprecated-version'});member.content({GI+'attribute',GI+'return-value',GI+'parameters'});meta=attrs(member);require(meta.get('astra.profile')=='declarations-v1' and member.attributes.get('throws')=='1','exact checked-out profile and throws metadata required')
		if 'astra.error-domain' in meta:
			require(meta['astra.error-domain']==str(error['domain']),'checked domain differs from selected mapping');require(meta.get('astra.error-codes','').split(',')==[str(c) for c in error['cases'].values()],'checked codes differ from selected mapping')
		return '[Foreign(error_factory='+json.dumps(error['factory'])+',error_domain='+json.dumps(str(error['domain']))+',errors='+json.dumps(','.join(k+'='+str(v) for k,v in error['cases'].items()))+')]'
	def declarations(obj,member,factory):
		ns=obj['namespace'];foreign=checked(member);symbol=ident(member.attributes.get(C+'identifier'));method='init' if factory else member.attributes.get('name','').removeprefix('try_');ident(method);require(symbol==obj['symbol']+('_new' if factory else '_try_'+method),'checked SDK symbol/member mismatch');returned=member.one(GI+'return-value');args,instances=parameter_list(member);require(len(args)<=4096,'method parameter bound')
		if factory:
			require(not instances and typed(returned)==(obj['name'],obj['ctype']+'*') and transfer(returned)=='full' and nullable(returned),'constructor exact nullable full result required')
		else:
			require(len(instances)==1 and typed(instances[0])==(obj['name'],obj['ctype']+'*') and transfer(instances[0])=='none' and not nullable(instances[0]),'exact borrowed instance required');require(typed(returned)==('gboolean','gboolean') and transfer(returned)=='none' and not nullable(returned),'checked method gboolean return required')
		result=None
		if not factory and args and args[-1].attributes.get('name')=='result':
			result_node=args[-1];require(result_node.attributes.get('direction')=='out' and result_node.attributes.get('caller-allocates')=='0','checked result must be an independent out slot');result=channel(result_node,ns,True);args=args[:-1]
		skip=set();params=[];annotations={};used=set()
		def annotate(name,**facts):
			values=annotations.setdefault(name,{})
			for key,value in facts.items():require(key not in values or values[key]==value,'conflicting native channel fact');values[key]=value
		for index,arg in enumerate(args):
			if index in skip:continue
			arg.attrs({'name','transfer-ownership','nullable','allow-none','direction','caller-allocates','scope','closure','destroy'});arg.content({GI+'type',GI+'array',GI+'attribute'});name=ident(arg.attributes.get('name'));require(name not in used and name!='result','duplicate/reserved parameter');used.add(name)
			arrays=children(arg,'array')
			if arrays:
				require(len(arrays)==1,'one bounded array required');array=arrays[0];array.attrs({'length','zero-terminated',C+'type'});require(array.attributes.get('zero-terminated')=='0' and array.attributes.get(C+'type')=='guint8**' and typed(array)==('guint8',None),'bounded output byte storage required');length=array.attributes.get('length','');require(length.isdecimal() and int(length)==index+1 and int(length)<len(args),'bounded array length must be the following exact slot');capacity=args[int(length)];require(typed(capacity)==('gint','gint*') and capacity.attributes.get('direction')=='inout' and transfer(capacity)=='none','bounded capacity slot mismatch');meta=attrs(arg);require(meta.get('astra.direction') in ('out','inout') and meta.get('astra.produced')=='result' and result and result['source']=='int','missing exact bounded direction/produced count');require(transfer(arg)=='none','bounded storage transfer mismatch');skip.add(int(length));value=dict(source='borrowed u8[]',kind='bytes',meta=meta,nullable=nullable(arg),direction=meta['astra.direction']);annotate(name,direction=value['direction'],produced='result')
			else:value=channel(arg,ns)
			if value['kind']=='callback':
				closure=arg.attributes.get('closure','');require(closure.isdecimal() and int(closure)==index+1 and int(closure)<len(args),'callback closure requires following userdata');data=args[int(closure)];require(typed(data)==('gpointer','gpointer') and transfer(data)=='none','callback userdata ABI mismatch');skip.add(int(closure))
			if value['kind']=='scalar' and value['direction'] in ('out','inout'):
				value['source']='borrowed '+value['source']+'*';annotate(name,direction=value['direction'])
			if value['kind']=='text':annotate(name,encoding=value['meta']['astra.encoding'])
			if value['nullable']:annotate(name,nullable='true')
			params.append(value['source']+' '+name)
		if result:
			if result['kind']=='text':annotate('result',encoding=result['meta']['astra.encoding'],transfer='full')
			if result['nullable']:annotate('result',nullable='true')
		text=foreign+''.join('[ForeignChannel(parameter='+json.dumps(name)+','+','.join(k+'='+json.dumps(v) for k,v in facts.items())+')]' for name,facts in annotations.items())+('init' if factory else (result['source'] if result else 'void')+' '+method)+'('+','.join(params)+')throws '+error['type']+';'
		contract.append(dict(owner=obj['namespace']+'.'+obj['name'],member=member.attributes.get('name'),symbol=symbol,declaration=text,result_source=result['source'] if result else 'void',parameters=params,attributes=attrs(member)))
		return text
	def signal(obj,name):
		ns=obj['namespace'];found=[n for n in obj['node'].children if n.tag==GLIB+'signal' and n.attributes.get('name')==name];require(len(found)==1,'missing/duplicate selected signal '+name);node=found[0]
		node.attrs({'name','when','version','introspectable','detailed','action','no-recurse','no-hooks'});node.content({GI+'attribute',GI+'return-value',GI+'parameters'});require(node.attributes.get('when')=='last' and node.attributes.get('introspectable','1')=='1' and all(node.attributes.get(k,'0')=='0' for k in ['detailed','action','no-recurse','no-hooks']),'unsupported signal dispatch profile');meta=attrs(node)
		require(meta=={'astra.profile':'declarations-v1','astra.signal-scope':'synchronous','astra.signal-closure':'gclosure','astra.signal-destroy':'finalized'},'signal requires exact synchronous scope, GClosure retention and finalization destruction facts')
		returned=node.one(GI+'return-value');returned.attrs({'transfer-ownership','nullable','allow-none'});returned.content({GI+'type'});require(typed(returned)==('none','void') and transfer(returned)=='none' and not nullable(returned),'retained signal requires nonthrowing void result');args,instances=parameter_list(node,True);require(not instances,'signal cannot declare an instance parameter');require(len(args)<=4,'native retained Closure supports at most four logical inputs');types=[];names=set()
		for argument in args:
			argument_name=ident(argument.attributes.get('name'));require(argument_name not in names,'duplicate signal argument name');names.add(argument_name);require(not set(argument.attributes).intersection({'scope','closure','destroy'}),'copied signal argument cannot carry callback retention metadata');value=channel(argument,ns);require(value['kind']=='scalar' and value['source']!='void' and value['direction']=='in' and transfer(argument)=='none','native retained signal callback requires supported copied scalar arguments');types.append(value['source'])
			# Same immutable ForeignValueType identity used by the native physical plan.
		codes={'int':1,'u32':2,'i64':3,'u64':4,'f32':5,'f64':6,'bool':7};value_identity=lambda code:str(code)+':0::0:0:-;';identity='14:0::0:'+str(len(types))+':'+''.join(value_identity(codes[t]) for t in types)+value_identity(0)
		item=dict(kind='retained-signal',owner=ns+'.'+obj['name'],name=name,source=obj['source']+'_signal_'+name.replace('-','_')+'_source',parameters=types,callback_identity=identity,attributes=meta,prefix=obj['prefix'],get_type=obj['get_type'],ctype=obj['ctype']);signal_bindings.append(item);contract.append(item)
	bodies=[]
	for key,obj in sorted(objects.items()):
		members=[]
		for name in obj['constructors']:members.append(declarations(obj,only(obj['node'],'constructor',name),True))
		for name in obj['methods']:members.append(declarations(obj,only(obj['node'],'method',name),False))
		for name in obj['properties']:
			prop=only(obj['node'],'property',name);native_name=ident(name.replace('-','_'));get='try_get_'+native_name;set_='try_set_'+native_name;writable=prop.attributes.get('writable','0')=='1';require(get in obj['methods'] and (not writable or set_ in obj['methods']),'property requires selected typed accessors');require(prop.attributes.get('construct-only','0')=='0' and prop.attributes.get('readable','1')=='1','property access mismatch')
			getter=next(c for c in contract if c.get('owner')==key and c.get('member')==get);ret=getter['result_source'];require(not getter['parameters'],'property getter takes no arguments');require(prop.one(GI+'type').attributes.get('name')==only(obj['node'],'method',get).one(GI+'parameters').children[-1].one(GI+'type').attributes.get('name'),'property/getter type mismatch');declaration=getter['declaration'];require(declaration in members,'property getter selected once');members.remove(declaration)
			declaration=declaration.replace(ret+' get_'+native_name+'()throws '+error['type']+';', 'property '+ret+' '+native_name+' throws '+error['type']+'{get;'+('set('+ret+' argument0);' if writable else '')+'}')
			if writable:
				setter=next(c for c in contract if c.get('owner')==key and c.get('member')==set_);require(setter['result_source']=='void' and setter['parameters']==[ret+' argument0'],'property setter type mismatch');members.remove(setter['declaration'])
			members.append(declaration);contract.append(dict(owner=key,property=name,declaration=declaration,attributes=dict(prop.attributes)))
		for name in obj['signals']:signal(obj,name)
		bindings='|'.join(records[k]['source']+'='+records[k]['ctype']+':'+records[k]['prefix'] for k in sorted(records))
		fields=dict(name=obj['prefix'],type=obj['ctype'],namespace=obj['namespace'],version=profile['namespaces'][obj['namespace']],symbol_prefix=obj['symbol'],header=obj['header'],threading='constructing',profile='declarations-v1')
		if bindings:fields['records']=bindings
		bodies.append('[GObjectImport('+','.join(k+'='+json.dumps(v) for k,v in fields.items())+')]class '+obj['source']+'{\n'+'\n'.join(members)+'\n}')
	lines=['// Generated typed declarations from selected checked-out GIR facts.']
	for key,value in sorted(records.items()):lines.append('struct '+value['source']+'{'+''.join(t+' '+n+';' for n,t in value['fields'])+'}')
	lines+=bodies
	files={}
	if signal_bindings:
		require('GirSignal16' not in sources,'signal Resource source identity collision');generated_prefix='astra_gir16_'+hashlib.sha256(profile_bytes+entry_bytes+Path(__file__).read_bytes()).hexdigest()+'_';handle_free=generated_prefix+'signal_source_free';mode=generated_prefix+'signal_mode';vapi=['[CCode(destroy_function='+json.dumps(handle_free)+')]handle GirSignal16;','[GObjectImport(name='+json.dumps(mode)+',header="bindings.h")]int gir_signal16_mode(borrowed GirSignal16 source);']
		header=['/* Generated declarations-v1 typed signal bridge. */','#pragma once','#include <stdint.h>','#ifdef __cplusplus','extern "C" {','#endif',f'void {handle_free}(void *);',f'int32_t {mode}(void *);'];code=['/* Generated synchronous typed GClosure marshallers; no application algorithms. */','#include "bindings.h"','#include "gobject-signals-16.h"','#include <stdbool.h>']
		code += [f'void {handle_free}(void *source) {{ astra_gobject16_signal_source_free(source); }}',f'int32_t {mode}(void *source) {{ return astra_gobject16_signal_mode(source); }}']
		physical={'int':('int32_t','G_TYPE_INT','g_value_get_int'),'u32':('uint32_t','G_TYPE_UINT','g_value_get_uint'),'i64':('int64_t','G_TYPE_INT64','g_value_get_int64'),'u64':('uint64_t','G_TYPE_UINT64','g_value_get_uint64'),'f32':('float','G_TYPE_FLOAT','g_value_get_float'),'f64':('double','G_TYPE_DOUBLE','g_value_get_double'),'bool':('bool','G_TYPE_BOOLEAN','g_value_get_boolean')}
		for item in signal_bindings:
			name=ident(item['source']);symbol=generated_prefix+name;marshal=symbol+'_marshal';params=item['parameters'];prototype='void *context'+''.join(', '+physical[t][0]+' argument'+str(i) for i,t in enumerate(params));header.append(f'void *{symbol}(void *self);');vapi.append('[GObjectImport(name='+json.dumps(symbol)+',header="bindings.h",carrier='+json.dumps(objects[item['owner']]['source'])+')]owned GirSignal16 '+name+'(borrowed '+objects[item['owner']]['source']+' self);');code += [f'typedef struct {item["prefix"]}_handle {item["prefix"]}_handle;',f'extern void *{item["prefix"]}_root_identity({item["prefix"]}_handle *);',f'extern GType {item["get_type"]}(void);',f'typedef void (*{symbol}_Callback)({prototype});',f'static void {marshal}(GClosure *closure, GValue *result, guint count, const GValue *values, gpointer hint, gpointer extra) {{',f'(void)result; (void)hint; (void)extra; if (count != {len(params)+1} || !G_VALUE_HOLDS_OBJECT(&values[0])) {{ g_error("signal marshaller lost exact parameter inventory"); }}',f'void *connection = closure->data; if (astra_gobject16_signal_enter(connection) != 1) return; {symbol}_Callback callback = ({symbol}_Callback)astra_gobject16_signal_callback(connection);']
			arguments=['astra_gobject16_signal_context(connection)']+[physical[t][2]+f'(&values[{i+1}])'+(' != FALSE' if t=='bool' else '') for i,t in enumerate(params)];code += ['callback('+', '.join(arguments)+');','astra_gobject16_signal_leave(connection);','}',f'void *{symbol}(void *self) {{ GObject *object = {item["prefix"]}_root_identity(self); if (!object || !G_TYPE_CHECK_INSTANCE_TYPE(object, {item["get_type"]}())) return NULL;']
			if params:code.append('const GType types[] = {'+', '.join(physical[t][1] for t in params)+'};')
			code += [f'return astra_gobject16_signal_source(object, {json.dumps(item["name"])}, {json.dumps(item["callback_identity"])}, {marshal}, {len(params)}, '+('types' if params else 'NULL')+');','}']
		header+=['#ifdef __cplusplus','}','#endif'];files['bindings.h']=('\n'.join(header)+'\n').encode();files['bindings.c']=('\n'.join(code)+'\n').encode();files['bindings.vapi']=('\n'.join(vapi)+'\n').encode()
	files['bindings.astra']=('\n'.join(lines)+'\n').encode();packages={}
	for package in profile['packages']:
		require(isinstance(package,str) and re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_.-]*',package),'unsafe package');p=subprocess.run(['pkg-config','--modversion',package],capture_output=True,text=True,timeout=20);require(p.returncode==0,'selected package unavailable');packages[package]=p.stdout.strip()
	metadata=dict(format='astra-gir-declarations-contract/1',target=profile['target'],profile_sha256=hashlib.sha256(profile_bytes).hexdigest(),gir_sha256=inputs,packages=packages,generator_sha256=hashlib.sha256(entry_bytes+Path(__file__).read_bytes()).hexdigest(),objects=[{k:v for k,v in obj.items() if k!='node'} for obj in objects.values()],records=records,callbacks=callbacks,api=contract,products={name:hashlib.sha256(data).hexdigest() for name,data in files.items()})
	metadata['fingerprint']=hashlib.sha256(json.dumps(metadata,sort_keys=True,separators=(',',':')).encode()).hexdigest();files['contract.json']=(json.dumps(metadata,sort_keys=True,indent=2)+'\n').encode();return files
