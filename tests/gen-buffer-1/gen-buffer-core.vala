// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Semantic;
using Astra.Core;
namespace Astra.Tests.GenericBufferCore {
private void qualify() {
	try {
		CoreProgram? symbolic = sample ();
		var definition = WeakRef (symbolic.generic_functions[0]);
		var premise = WeakRef (symbolic.generic_functions[0].element_obligations);
		var cleanup = WeakRef (symbolic.cleanups[0]);
		CoreVerifier.verify (symbolic);
		var concrete = CoreGenericMonomorphizer.build (symbolic);
		symbolic = null;
		assert (definition.get () == null && premise.get () == null && cleanup.get () == null);
		CoreVerifier.verify_concrete (concrete);
		assert (concrete.cleanups.length == 1 && concrete.cleanups[0].is_buffer && !concrete.cleanups[0].is_symbolic_buffer);
		assert (concrete.functions[1].owned_cleanup == concrete.cleanups[0] && concrete.functions[1].owned_locals.length == 1);
		assert (concrete.functions[1].owned_locals[0].place == concrete.functions[1].locals[0]);
	} catch (CoreError error) {
		GLib.error ("%s", error.message);
	}
	for (int variant = 0; variant < 17; variant++) {
		var program = sample ();
		var generic = program.generic_functions[0];
		var owner = generic.owned_locals[0];
		var t = generic.type_parameters[0].semantic_type;
		if (variant < 4) {
			generic.element_obligations.require (t, (GenericElementRequirements) ((int) GenericElementRequirements.BUFFER & ~(1 << variant)));
		}
		if (variant == 4) {
			generic.element_obligations.require (new TypeParameterType ("T"));
		}
		if (variant == 5) {
			generic.owned_locals.remove_index (0);
		}
		if (variant == 6) {
			generic.body.statements[2] = new CoreOwnershipReturn (generic.span, generic.return_type, generic.owned_cleanup, null);
		}
		if (variant == 7) {
			generic.body.statements.insert (2, new CoreOwnershipRelease (generic.span, owner, owner.cleanup));
		}
		if (variant == 8) {
			generic.body.statements.insert (2, new CoreOwnershipRearm.from_owner (generic.span, owner, owner, owner.cleanup));
		}
		if (variant == 9) {
			program.cleanups.remove_index (0);
		}
		if (variant == 10) {
			generic.locals[0].semantic_type = new SliceType (new TypeParameterType ("T"));
		}
		if (variant == 11) {
			generic.body.statements[2] = new CoreReturn (generic.span, new CoreOwnedBufferBorrow (generic.span, owner, null));
		}
		if (variant == 12 || variant == 13) {
			var function = variant == 12 ? (CoreFunction) generic : program.functions[0];
			var original = (CoreInitialize) function.body.statements[0];
			var fresh = new CoreLocalPlace (generic.span, generic.span, "duplicate", original.target.semantic_type, function.locals.length);
			var duplicate = new CoreOwnedLocal (generic.span, fresh, original.acquisition.cleanup, function.body);
			function.locals.add (fresh);
			function.owned_locals.add (duplicate);
			function.body.statements.insert (1, new CoreInitialize (generic.span, fresh, original.value, duplicate));
		}
		if (variant == 14) {
			generic.owned_locals[0] = new CoreOwnedLocal (generic.span, owner.place, owner.cleanup, program.functions[0].body);
		}
		if (variant == 15 || variant == 16) {
			var bool_type = new BuiltinTypes ().bool_type;
			var condition = new CoreParameter (generic.span, generic.span, "condition", bool_type, 1);
			generic.parameters.add (condition);
			((CoreGenericCall) ((CoreInitialize) program.functions[0].body.statements[0]).value).arguments.add (new CoreBooleanValue (generic.span, bool_type, BooleanLiteral.TRUE));
			var block = new CoreBlock (generic.span, new GenericArray<CoreStatement> ());
			block.statements.add (new CoreOwnershipRelease (generic.span, owner, owner.cleanup));
			if (variant == 15) {
				generic.body.statements.insert (2, new CoreIf (generic.span, new CoreParameterValue (generic.span, condition), block, null));
			} else {
				generic.body.statements.insert (2, new CoreWhile (generic.span, new CoreLoopTarget (generic.span, 0), new CoreParameterValue (generic.span, condition), block));
			}
		}
		bool rejected = false;
		try {
			CoreVerifier.verify (program);
		} catch (CoreError error) {
			Test.message ("symbolic variant %d: %s", variant, error.message);
			if (variant >= 15) {
				assert (error.message.contains ("generic ownership flow"));
			}
			rejected = true;
		}
		assert (rejected);
	}
	for (int variant = 0; variant < 4; variant++) {
		try {
			var concrete = CoreGenericMonomorphizer.build (sample ());
			var function = concrete.functions[1];
			if (variant == 0) {
				function.generic_instance.type_arguments[0] = new BuiltinTypes ().f64_type;
			}
			if (variant == 1) {
				var types = new BuiltinTypes ();
				function.owned_cleanup.buffer_shape = new BufferValueShape (types.slice_of (types.f64_type), function.owned_cleanup.buffer_shape.base_type, function.owned_cleanup.buffer_shape.length_type);
			}
			if (variant == 2) {
				var owner = function.owned_locals[0];
				function.body.statements.insert (2, new CoreOwnershipRelease (function.span, owner, owner.cleanup));
				function.body.statements.insert (3, new CoreInitialize (function.span, function.locals[1], ((CoreInitialize) function.body.statements[1]).value));
			}
			if (variant == 3) {
				concrete.cleanups.remove_index (0);
			}
			bool rejected = false;
			try {
				CoreVerifier.verify_concrete (concrete);
			} catch (CoreError error) {
				Test.message ("concrete variant %d: %s", variant, error.message);
				rejected = true;
			}
			assert (rejected);
		} catch (CoreError error) {
			GLib.error ("%s", error.message);
		}
	}
}
public int run_core(string[] args) {
	Test.init (ref args);
	Test.add_func ("/gen-buffer/core/independent-premises-owners-producers-and-lifetimes", qualify);
	return Test.run ();
}
}
