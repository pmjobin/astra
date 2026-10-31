// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Syntax;

namespace Astra.Tests.AsyncParser {
private ParseResult parse(string source) {
	return Parser.parse (new SourceFile.from_text ("async-source", source));
}
private void bodies() {
	var parsed = parse ("async owned u8[] delayed(owned u8[] data)throws Error{await delay_ticks(2);return move data;}async void application()throws Error{var work=delayed(new u8[4]);start(work);try{await delay_ticks(1);}catch(Error e){await cancel_and_join(move work);throw;}var bytes=await move work;}");
	assert (parsed.diagnostic == null);
	assert (parsed.unit.functions[0].is_async && parsed.unit.functions[1].is_async);
	assert (parsed.unit.functions[0].span.text ().has_prefix ("async owned"));
	assert (parsed.unit.functions[0].owned_keyword != null);
	assert (parsed.unit.functions[0].throws_class.spelling () == "Error");
	assert (((AwaitStatementSyntax) parsed.unit.functions[0].body.statements[0]).expression.operation is CallExpressionSyntax);
	var local = (InferredLocalDeclarationSyntax) parsed.unit.functions[1].body.statements[3];
	assert (((AwaitExpressionSyntax) local.initializer).operation is MoveExpressionSyntax);
}
private void malformed() {
	foreach (string source in new string[] { "async int f<T>(){return 0;}", "extern(C)async void f();", "async extern(C)void f();", "class C{async void f(){}}", "async void f(){await;}", "async void f(){await move;}", "async void f(){await delay_ticks(1) + 2;}", "int await(){return 0;}", "int async(){return 0;}" }) {
		assert (parse (source).diagnostic != null);
	}
}
private void compatibility() {
	var nomination = parse ("async runtime Executor throws Failure returns Status;");
	assert (nomination.diagnostic == null && nomination.unit.async_runtimes.length == 1);
	assert (SyntaxDump.format (nomination.unit).contains ("async-runtime Executor throws Failure returns Status"));
	assert (parse ("int yield(int capture,int finally,int start,int cancel,int run,int delay_ticks){return capture;}").diagnostic == null);
	assert (parse ("int f(){return 2;}int main(){return f();}").diagnostic == null);
}
int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/async-1/parser/declarations-await-move-and-cleanup", bodies);
	Test.add_func ("/async-1/parser/malformed-and-deferred-boundaries", malformed);
	Test.add_func ("/async-1/parser/narrow-keywords-and-synchronous-compatibility", compatibility);
	return Test.run ();
}
}
