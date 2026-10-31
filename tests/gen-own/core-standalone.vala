// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Semantic;
using Astra.Core;
namespace Astra.Tests.GenOwnCore {
private void double_move(CoreProgram program, bool conditional = false) {
	var caller = program.generic_functions[1];
	var sink = program.generic_functions[0];
	var owner = caller.owned_locals[0];
	var arguments = new GenericArray<CoreValue> ();
	arguments.add (new CoreOwnedArgumentValue (caller.span, sink.parameters[0], owner.cleanup, owner, caller.return_type));
	var actuals = new GenericArray<SemanticType> ();
	actuals.add (caller.return_type);
	var move = new CoreGenericCallStatement (caller.span, sink, actuals, arguments);
	var returned = caller.body.statements[1];
	caller.body.statements.remove_index (1);
	if (conditional) {
		var branch = new CoreBlock (caller.span, new GenericArray<CoreStatement> ());
		branch.statements.add (move);
		caller.body.statements.add (new CoreIf (caller.span, new CoreBooleanValue (caller.span, new BuiltinTypes ().bool_type, BooleanLiteral.TRUE), branch, null));
	} else {
		caller.body.statements.add (move);
	}
	caller.body.statements.add (returned);
}
private void valid() {
	try {
		foreach (bool resource in new bool[] {false, true}) {
			var p = sample (resource);
			CoreVerifier.verify (p);
			assert (p.generic_functions[1].type_parameters[0].transport_mode == GenericTransportMode.OWNABLE);
			assert (p.generic_functions[1].owned_cleanup.type_parameter == p.generic_functions[1].return_type && p.generic_functions[1].result_storage == null);
			assert (CoreDump.format (p).contains ("(transport OWNABLE)"));
		}
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
private void invalid() {
	for (int variant = 0; variant < 7; variant++) {
		var p = sample (false, false, true);
		var f = p.generic_functions[1];
		if (variant <= 1) {
			double_move (p, variant == 1);
		}
		if (variant == 2) {
			f.locals.add (new CoreLocalPlace (f.span, f.span, "forbidden", f.return_type, 1));
		}
		if (variant == 3) {
			f.body.statements.remove_index (1);
			f.body.statements.add (new CoreOwnershipReturn (f.span, f.return_type, f.owned_cleanup, null));
		}
		if (variant == 4) {
			f.body.statements.remove_index (1);
			f.body.statements.add (new CoreReturn (f.span, new CoreLoadValue (f.span, f.locals[0])));
		}
		if (variant == 5) {
			f.body.statements.remove_index (1);
			f.body.statements.add (new CoreOwnershipReturn (f.span, f.return_type, p.generic_functions[0].owned_locals[0].cleanup, f.owned_locals[0]));
		}
		if (variant == 6) {
			p.generic_functions[2].capability_requirements.remove_index (0);
		}
		try {
			CoreVerifier.verify (p);
		} catch (CoreError error) {
			if (variant <= 1) {
				assert (error.message.contains ("use of moved owned value"));
			}
			continue;
		}
		GLib.error ("accepted forged generic ownership %d", variant);
	}
}
private void exact_loop_targets() {
	foreach (bool continued in new bool[] {false, true}) {
		foreach (bool moved in new bool[] {false, true}) {
			var p = sample (false, false, true);
			var f = p.generic_functions[1];
			var sink = p.generic_functions[0];
			var owner = f.owned_locals[0];
			var types = new BuiltinTypes ();
			var outer = new CoreLoopTarget (f.span, 0);
			var inner = new CoreLoopTarget (f.span, 1);
			var unreachable = new CoreLoopTarget (f.span, 2);
			var outer_body = new CoreBlock (f.span, new GenericArray<CoreStatement> ());
			var inner_body = new CoreBlock (f.span, new GenericArray<CoreStatement> ());
			var arguments = new GenericArray<CoreValue> ();
			arguments.add (new CoreOwnedArgumentValue (f.span, sink.parameters[0], owner.cleanup, owner, f.return_type));
			var actuals = new GenericArray<SemanticType> ();
			actuals.add (f.return_type);
			if (moved) {
				inner_body.statements.add (new CoreGenericCallStatement (f.span, sink, actuals, arguments));
			}
			inner_body.statements.add (continued ? (CoreStatement) new CoreContinue (f.span, outer) : new CoreBreak (f.span, outer));
			outer_body.statements.add (new CoreWhile (f.span, inner, new CoreBooleanValue (f.span, types.bool_type, BooleanLiteral.TRUE), inner_body));
			outer_body.statements.add (new CoreWhile (f.span, unreachable, new CoreBooleanValue (f.span, types.bool_type, BooleanLiteral.TRUE), new CoreBlock (f.span, new GenericArray<CoreStatement> ())));
			var returned = f.body.statements[1];
			f.body.statements.remove_index (1);
			f.body.statements.add (new CoreWhile (f.span, outer, new CoreBooleanValue (f.span, types.bool_type, BooleanLiteral.TRUE), outer_body));
			f.body.statements.add (returned);
			bool rejected = false;
			try {
				CoreVerifier.verify (p);
			} catch (CoreError error) {
				assert (error.message.contains ("moved") && error.message.contains ("owned value"));
				rejected = true;
			}
			assert (rejected == moved);
		}
	}
}
int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/gen-own/core/exact-parameterized-contracts", valid);
	Test.add_func ("/gen-own/core/unused-state-copy-local-null-provenance-forgeries", invalid);
	Test.add_func ("/gen-own/core/exact-enclosing-loop-target-state", exact_loop_targets);
	return Test.run ();
}
}
