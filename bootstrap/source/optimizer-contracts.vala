// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
namespace Astra.Source {
public class FloatingPointPermissions : Object {
	public const uint SUPPORTED = 63;
	public static bool valid(uint permissions) {
		return (permissions & ~SUPPORTED) == 0;
	}
}
public class FunctionEffectFacts : Object {
	public const uint RECEIVER_NO_CAPTURE = 1;
	public const uint RECEIVER_READONLY = 2;
	public const uint NO_EXTERNAL_MEMORY = 4;
	// The initializer body is readonly. The ordinary cache gate still writes
	// hidden state; this bit never becomes a readonly/memory(none) gate attr.
	public const uint LAZY_READONLY_FACTORY = 8;
	public uint flags { get; internal set; }
	private uint original;
	private uint[] formals;
	public int parameter_count { get { return formals.length; } }
	public uint parameter(int ordinal) {
		return ordinal >= 0 && ordinal < formals.length ? formals[ordinal] : 0;
	}
	public FunctionEffectFacts (uint flags, uint[]? parameters = null) {
		this.flags = flags;
		original = flags;
		formals = parameters == null ? new uint[0] : parameters.copy ();
	}
	public FunctionEffectFacts copy() {
		var result = new FunctionEffectFacts (original, formals);
		result.flags = flags;
		return result;
	}
	public bool same(FunctionEffectFacts other) {
		if (flags != other.flags || formals.length != other.formals.length) {
			return false;
		}
		for (int i = 0; i < formals.length; i++) {
			if (formals[i] != other.formals[i]) {
				return false;
			}
		}
		return true;
	}
	public bool valid() {
		foreach (uint formal in formals) {
			if ((formal & ~3U) != 0) {
				return false;
			}
		}
		return flags == original && (flags & ~15U) == 0 && ((flags & LAZY_READONLY_FACTORY) == 0 || (flags & RECEIVER_NO_CAPTURE) != 0);
	}
}

public errordomain OptimizerSummaryError {
	INVALID
}
// Issued only after typed module binding and native object validation. This
// detached receipt retains no source, SSA, native plan or implementation body.
public class NativeOptimizerEvidence : Object {
	private string checked_symbol;
	private string checked_signature;
	private string checked_object_hash;
	public string symbol { get { return checked_symbol; } }
	public string signature { get { return checked_signature; } }
	public string object_hash { get { return checked_object_hash; } }
	private FunctionEffectFacts checked_facts;
	internal NativeOptimizerEvidence (string symbol, string signature, string object_hash, FunctionEffectFacts facts) {
		checked_symbol = symbol;
		checked_signature = signature;
		checked_object_hash = object_hash;
		checked_facts = facts.copy ();
	}
	public FunctionEffectFacts facts() {
		return checked_facts.copy ();
	}
	public bool permits(FunctionEffectFacts facts) {
		return facts.valid () && checked_facts.same (facts);
	}
}
public class OptimizerParameterSummary : Object {
	public int ordinal { get; private set; }
	public uint facts { get; private set; }
	public OptimizerParameterSummary (int ordinal, uint facts) {
		this.ordinal = ordinal;
		this.facts = facts;
	}
}
// Declaration grammar only. Decoding never supplies optimizer authority.
public class OptimizerSummary : Object {
	public const string HEADER = "astra-optimizer-summary/1";
	public bool memory_none { get; private set; }
	private GenericArray<OptimizerParameterSummary> parameters = new GenericArray<OptimizerParameterSummary> ();
	public uint count { get { return parameters.length; } }
	public OptimizerParameterSummary parameter(uint at) {
		return parameters[at];
	}
	public OptimizerSummary (bool memory_none = false) {
		this.memory_none = memory_none;
	}
	public void add(int ordinal, uint facts) throws OptimizerSummaryError {
		if (ordinal < -1 || (facts & ~3U) != 0 || parameters.length != 0 && parameters[parameters.length - 1].ordinal >= ordinal) {
			throw new OptimizerSummaryError.INVALID ("optimizer rows require sorted unique logical formal ordinals and supported effects");
		}
		parameters.add (new OptimizerParameterSummary (ordinal, facts));
	}
	public string encode() {
		var text = new StringBuilder (HEADER + "\nmemory|" + (memory_none ? "none" : "unknown"));
		foreach (var row in parameters) {
			text.append_printf ("\np|%d|%s|%s", row.ordinal, (row.facts & 1) != 0 ? "none" : "unknown", (row.facts & 2) != 0 ? "readonly" : "unknown");
		}
		return text.str;
	}
	public static OptimizerSummary decode(string text) throws OptimizerSummaryError {
		var lines = text.split ("\n");
		if (lines.length < 2 || lines[0] != HEADER || (lines[1] != "memory|none" && lines[1] != "memory|unknown")) {
			throw new OptimizerSummaryError.INVALID ("invalid optimizer summary version or memory effect");
		}
		var result = new OptimizerSummary (lines[1] == "memory|none");
		for (int i = 2; i < lines.length; i++) {
			var fields = lines[i].split ("|");
			int ordinal = -2;
			if (fields.length != 4 || fields[0] != "p" || !int.try_parse (fields[1], out ordinal) || ordinal.to_string () != fields[1] ||
			    (fields[2] != "none" && fields[2] != "unknown") || (fields[3] != "readonly" && fields[3] != "unknown")) {
				throw new OptimizerSummaryError.INVALID ("invalid canonical optimizer parameter row");
			}
			result.add (ordinal, (fields[2] == "none" ? 1U : 0U) | (fields[3] == "readonly" ? 2U : 0U));
		}
		return result;
	}
}
}
