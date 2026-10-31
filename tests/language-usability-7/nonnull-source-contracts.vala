// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;

namespace Astra.Tests.NonNullSource {
private CheckedProgram sample(string body) {
	var parsed = Parser.parse (new SourceFile.from_text ("nonnull-proof.astra",
		"class C {int value;init(){this.value=7;}} int use(C input){return input.value;} int f(C input){" + body + "}"));
	assert (parsed.diagnostic == null);
	var checked = SemanticAnalyzer.analyze (parsed.unit);
	if (checked.diagnostic != null) {
		GLib.error ("%s", checked.diagnostic.format ());
	}
	return checked.program;
}
private CheckedFunction function(CheckedProgram program, string name) {
	foreach (var definition in program.functions) {
		if (definition.symbol.name == name) {
			return definition;
		}
	}
	assert_not_reached ();
}
private Diagnostic? proof(CheckedProgram program) {
	var selected = new GenericArray<FunctionSymbol> ();
	selected.add (function (program, "f").symbol);
	return SemanticNonNull.check (program, selected);
}
private void branch_refinement() {
	foreach (string body in new string[] {
			"if(input!=null){return use(input);}return 0;",
			"if(input==null){return 0;}return use(input);",
			"if(input!=null && use(input)==7){return 1;}return 0;",
			"if(input==null || use(input)==7){return 1;}return 0;",
			"while(input!=null){return use(input);}return 0;"
		}) {
		var program = sample (body);
		var target = function (program, "use").symbol;
		target.parameters[0].mark_nonnull ();
		assert (proof (program) == null);
	}
}
private void reject_unproven() {
	foreach (string body in new string[] {
			"return use(input);",
			"if(input!=null){use(input);}return use(input);",
			"C local=input;bool prior=local!=null;local=null;if(prior){return use(local);}return 0;",
			"C local=input;if(local==null){return 0;}while(true){use(local);local=null;}return 1;"
		}) {
		var program = sample (body);
		var target = function (program, "use").symbol;
		target.parameters[0].mark_nonnull ();
		var rejected = proof (program);
		assert (rejected != null && rejected.message.contains ("current non-null proof") && rejected.span.file.path == "nonnull-proof.astra");
	}
}
private void stale_capture() {
	var slot = new Object ();
	var captured = new Object ();
	var state = new NonNullFacts ();
	state.assign (slot, false);
	state.capture (captured, false, slot);
	var current = state.copy ();
	current.refine (captured);
	assert (current.knows (slot));
	state.assign (slot, false);
	state.refine (captured);
	assert (state.knows (captured) && !state.knows (slot));
	assert (!NonNullFacts.join (current, state).knows (slot));
}
private void checked_argument() {
	var program = sample ("if(input!=null){return use(input);}return 0;");
	function (program, "use").symbol.parameters[0].mark_nonnull ();
	assert (proof (program) == null);
	var branch = (CheckedIf) function (program, "f").body.statements[0];
	var call = (CheckedCallExpression) ((CheckedReturnStatement) branch.then_body.statements[0]).expression;
	var argument = call.arguments[0];
	call.arguments[0] = new CheckedNullPointerExpression (argument.span, argument.semantic_type);
	assert (proof (program) != null);
	call.arguments[0] = argument;
	assert (proof (program) == null);
}
private void nullable_defaults() {
	var program = sample ("return use(input);");
	foreach (var definition in program.functions) {
		assert (!definition.symbol.nonnull_result);
		foreach (var parameter in definition.symbol.parameters) {
			assert (!parameter.requires_nonnull);
		}
	}
	assert (proof (program) == null);
}
int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/nonnull-source/branch-and-short-circuit", branch_refinement);
	Test.add_func ("/nonnull-source/unproven-and-join", reject_unproven);
	Test.add_func ("/nonnull-source/stale-capture", stale_capture);
	Test.add_func ("/nonnull-source/checked-argument-restore", checked_argument);
	Test.add_func ("/nonnull-source/nullable-defaults", nullable_defaults);
	return Test.run ();
}
}
