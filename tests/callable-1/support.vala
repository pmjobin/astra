// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;
using Astra.Core;
using Astra.Cfg;
using Astra.Ssa;
using Astra.Continuations;

namespace Astra.Tests.Continuations {
private SsaFunction named(SsaProgram program, string name) {
	foreach (var function in program.functions) {
		if (function.name == name) {
			return function;
		}
	}
	assert_not_reached ();
}
private SsaProgram bodies() throws GLib.Error {
	string source;
	FileUtils.get_contents ("tests/callable-1/fixtures/bodies.astra", out source);
	ParseResult? parsed = Parser.parse (new SourceFile.from_text ("callable-bodies.astra", source));
	assert (parsed.diagnostic == null);
	var syntax = WeakRef (parsed.unit);
	SemanticResult? checked = SemanticAnalyzer.analyze (parsed.unit);
	parsed = null;
	assert (syntax.get () == null);
	if (checked.diagnostic != null) {
		GLib.error ("%s", checked.diagnostic.format ());
	}
	var semantic = WeakRef (checked.program.types);
	var checked_function = WeakRef (checked.program.functions[0]);
	CoreProgram? core = CoreBuilder.build (checked.program);
	checked = null;
	assert (semantic.get () == null && checked_function.get () == null);
	CoreVerifier.verify (core);
	var old_core = WeakRef (core);
	core = CoreGenericMonomorphizer.build (core);
	assert (old_core.get () == null);
	CoreVerifier.verify (core);
	var core_function = WeakRef (core.functions[0]);
	CfgProgram? cfg = CfgBuilder.build (core);
	core = null;
	assert (core_function.get () == null);
	CfgVerifier.verify (cfg);
	assert (CfgFlowChecker.check (cfg).diagnostic == null);
	var cfg_function = WeakRef (cfg.functions[0]);
	var result = SsaBuilder.build (cfg);
	cfg = null;
	assert (cfg_function.get () == null);
	SsaVerifier.verify (result);
	return result;
}
private void add_call(SsaContinuationRegion region, int owner, int witness, ContinuationRole role = ContinuationRole.STEP) {
	region.actions.add (new ContinuationAction (ContinuationActionKind.BEGIN, owner, -1, -1, -1, witness));
	region.actions.add (new ContinuationAction (ContinuationActionKind.CALL, owner, -1, -1, -1, witness, 1, -1, -1, role));
	region.actions.add (new ContinuationAction (ContinuationActionKind.END, owner, -1, -1, -1, witness));
}
private SsaContinuationFamily family(SsaContinuationEnvironment? environment, SsaFunction step, SsaFunction alternate, SsaFunction cancel) {
	var result = new SsaContinuationFamily (environment, new SsaContinuationEntry (ContinuationRole.DESTROY, environment));
	result.entries.add (new SsaContinuationEntry (ContinuationRole.STEP, environment, step));
	result.entries.add (new SsaContinuationEntry (ContinuationRole.STEP, environment, alternate));
	result.entries.add (new SsaContinuationEntry (ContinuationRole.CANCEL_DRAIN, environment, cancel));
	return result;
}
private SsaProgram build() throws GLib.Error {
	var program = bodies ();
	var original = named (program, "generated_run");
	var selection = named (program, "selection");
	var span = original.span;
	var block = new SsaBlock (span, 0, 0);
	var args = new GenericArray<SsaValue> ();
	args.add (original.parameters[0]);
	var choose = new SsaCallInstruction (span, selection.return_type, 5, selection, args);
	block.instructions.add (choose);
	var region = new SsaContinuationRegion (span, original.return_type, 6);
	region.operands.add (choose.result);
	for (int i = 1; i < original.parameters.length; i++) {
		region.operands.add (original.parameters[i]);
	}
	var step = named (program, "step");
	SsaCleanupContract? buffer = null;
	foreach (var cleanup in program.cleanups) {
		if (cleanup.is_buffer) {
			buffer = cleanup;
		}
	}
	assert (buffer != null);
	var environment = new SsaContinuationEnvironment (step.return_type, step.struct_result, buffer);
	region.families.add (family (environment, step, named (program, "alternate"), named (program, "drain")));
	var scalar = named (program, "scalar_step");
	region.families.add (family (new SsaContinuationEnvironment (scalar.return_type), scalar, scalar, named (program, "scalar_drain")));
	region.families.add (family (null, named (program, "control"), named (program, "other_control"), named (program, "control")));
	for (int owner = 0; owner < 2; owner++) {
		region.actions.add (new ContinuationAction (ContinuationActionKind.CREATE, owner, -1, 0, owner));
		region.actions.add (new ContinuationAction (ContinuationActionKind.INITIALIZE, owner, -1, -1, -1, -1, 4, -1, -1, ContinuationRole.STEP, new int[] { 1, 2, 3 }));
		region.actions.add (new ContinuationAction (ContinuationActionKind.PUBLISH, owner, -1, -1, -1, -1, 0, 0, 1));
	}
	add_call (region, 0, 0);
	add_call (region, 0, 1);
	region.actions.add (new ContinuationAction (ContinuationActionKind.MOVE, 0, 2));
	region.actions.add (new ContinuationAction (ContinuationActionKind.RETAIN, 2, -1, -1, -1, 100));
	add_call (region, 2, 2, ContinuationRole.CANCEL_DRAIN);
	add_call (region, 2, 3);
	region.actions.add (new ContinuationAction (ContinuationActionKind.RELEASE, 2, -1, -1, -1, 100));
	region.actions.add (new ContinuationAction (ContinuationActionKind.DESTROY, 2));
	add_call (region, 1, 4);
	region.actions.add (new ContinuationAction (ContinuationActionKind.DESTROY, 1));
	region.actions.add (new ContinuationAction (ContinuationActionKind.CREATE, 3, -1, 1, 3));
	region.actions.add (new ContinuationAction (ContinuationActionKind.INITIALIZE, 3, -1, -1, -1, -1, -1, -1, -1, ContinuationRole.STEP, new int[] { 1 }));
	region.actions.add (new ContinuationAction (ContinuationActionKind.PUBLISH, 3, -1, -1, -1, -1, 0, 0, 1));
	add_call (region, 3, 5);
	add_call (region, 3, 6);
	region.actions.add (new ContinuationAction (ContinuationActionKind.DESTROY, 3));
	region.actions.add (new ContinuationAction (ContinuationActionKind.CREATE, 4, -1, 2, 4));
	region.actions.add (new ContinuationAction (ContinuationActionKind.PUBLISH, 4, -1, -1, -1, -1, 0, 0, 1));
	add_call (region, 4, 7);
	region.actions.add (new ContinuationAction (ContinuationActionKind.DESTROY, 4));
	block.instructions.add (region);
	var exit = new SsaBlock (span, 1, 1);
	var carried = new SsaBlockParameter.temporary (span, original.return_type, 7, 0);
	exit.parameters.add (carried);
	exit.complete (new SsaReturn (span, carried));
	var edge_arguments = new GenericArray<SsaValue> ();
	edge_arguments.add (region.result);
	block.complete (new SsaBranch (span, new SsaEdge (exit, edge_arguments)));
	var blocks = new GenericArray<SsaBlock> ();
	blocks.add (block);
	blocks.add (exit);
	var generated = new SsaFunction (span, original.name_span, original.name, original.return_type, original.ordinal, original.parameters, blocks, block);
	program.functions[original.ordinal] = generated;
	program.c_exports[0] = new SsaCExport (span, generated.name_span, generated, "generated_run", ForeignAbi.C, 0);
	SsaVerifier.verify (program);
	return program;
}
private SsaContinuationRegion region_of(SsaProgram program) {
	return (SsaContinuationRegion) named (program, "generated_run").entry.instructions[1];
}
}
