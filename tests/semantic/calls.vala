// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Semantic;

namespace Astra.Tests.Semantics {
private void call_identities() {
	var program = check_ok ("int first(int x){return second(x);} int second(int x){return first(x);} int self(int x){return self(x);}");
	int[] targets = {
		1, 0, 2
	};
	for (int i = 0; i < 3; i++) {
		var function = program.functions[i];
		var call = (CheckedCallExpression) returned_expression (function);
		assert (call.target == program.functions[targets[i]].symbol && call.semantic_type == program.types.int_type);
		assert (((CheckedParameterReferenceExpression) call.arguments[0]).parameter == function.symbol.parameters[0]);
	}
}

private void call_namespaces_and_statements() {
	var program = check_ok ("int name(int x){return x;} int f(int name){return name(name);} void g(){int name = name(1); name = name(name); name(name);} void ping(){return;} void h(){ping();}");
	var target = program.functions[0].symbol;
	var parameter_call = (CheckedCallExpression) returned_expression (program.functions[1]);
	assert (parameter_call.target == target);
	assert (((CheckedParameterReferenceExpression) parameter_call.arguments[0]).parameter == program.functions[1].symbol.parameters[0]);
	var function = program.functions[2];
	var declaration = (CheckedLocalDeclaration) function.body.statements[0];
	assert (((CheckedCallExpression) declaration.initializer).target == target);
	var assignment = (CheckedAssignment) function.body.statements[1];
	assert (assignment.target == function.locals[0] && ((CheckedCallExpression) assignment.expression).target == target);
	var discarded = (CheckedCallStatement) function.body.statements[2];
	assert (discarded.target == target && discarded.target.return_type == program.types.int_type);
	assert (((CheckedLocalReferenceExpression) discarded.arguments[0]).local == function.locals[0]);
	var ping = (CheckedCallStatement) program.functions[4].body.statements[0];
	assert (ping.target == program.functions[3].symbol && ping.arguments.length == 0);
	string dump = SemanticDump.format (program);
	assert (dump.contains ("(call-statement \"ping\" -> void (arguments))") && dump == SemanticDump.format (program));
}

private void call_error(string name, string text, string marker, string message) {
	register_error ("call-" + name, text, text.last_index_of (marker), marker.length, message);
}

private void register_call_semantic_tests() {
	Test.add_func ("/semantic/call/identities", call_identities);
	Test.add_func ("/semantic/call/namespaces-and-statements", call_namespaces_and_statements);
	register_program ("bool-calls", "bool p(int x){return x == 0;} bool f(){return !p(1);} int g(){if(p(0)){return 1;}else{return 2;}}", 3);
	register_program ("bool-argument", "bool id(bool x){return x;} bool f(){return id(true);}", 2);
	call_error ("unknown", "void f(){missing();}", "missing", "unknown function 'missing'");
	call_error ("local-not-callable", "void f(){int x = 1; x();}", "x", "unknown function 'x'");
	call_error ("parameter-not-callable", "void f(int x){x();}", "x", "unknown function 'x'");
	call_error ("too-few", "int add(int a,int b){return a+b;} void f(){add(1);}", "add(1)", "function 'add' expects 2 arguments, provided 1");
	call_error ("too-many", "int add(int a,int b){return a+b;} void f(){add(1,2,3);}", "add(1,2,3)", "function 'add' expects 2 arguments, provided 3");
	call_error ("wrong-first-type", "int add(int a,int b){return a+b;} void f(){add(true,2);}", "true", "argument 1 of function 'add' expects type 'int', provided 'bool'");
	call_error ("wrong-second-type", "int add(int a,int b){return a+b;} void f(){add(1,false);}", "false", "argument 2 of function 'add' expects type 'int', provided 'bool'");
	call_error ("void-return", "void ping(){return;} int f(){return ping();}", "ping()", "void function 'ping' cannot be used as a value");
	call_error ("void-initializer", "void ping(){return;} void f(){int x = ping();}", "ping()", "void function 'ping' cannot be used as a value");
	call_error ("void-assignment", "void ping(){return;} void f(){int x = 1; x = ping();}", "ping()", "void function 'ping' cannot be used as a value");
	call_error ("void-argument", "void ping(){return;} int id(int x){return x;} int f(){return id(ping());}", "ping()", "void function 'ping' cannot be used as a value");
	call_error ("void-condition", "void ping(){return;} void f(){if(ping()){}}", "ping()", "void function 'ping' cannot be used as a value");
	call_error ("void-prefix", "void ping(){return;} int f(){return -ping();}", "ping()", "void function 'ping' cannot be used as a value");
	call_error ("void-binary", "void ping(){return;} int f(){return 1 + ping();}", "ping()", "void function 'ping' cannot be used as a value");
	call_error ("argument-order", "int add(int a,int b){return a+b;} int f(){return add(left(),right());}", "left", "unknown function 'left'");
	call_error ("checked-after-return", "int f(){return 1; missing();}", "missing", "unknown function 'missing'");
}
}
