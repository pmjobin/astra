// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
namespace Astra.Source {
// Canonical compiler vocabulary. Registration never grants an implementation
// or ABI: reserved/candidate policies remain unavailable to source programs.
public enum DeclarationPolicyId {
	INVALID, SHARED, MONITOR, SINGLETON, THREAD_BOUND, ACTOR,
	ALLOCATOR, ALIGN, REPR, EXCEPTION_ROOT, C_CODE, FLOATING_POINT,
	UTF8_MESSAGE_FACTORY, CALLER_FILE, CALLER_LINE, CALLER_ARGUMENT,
	C_IMPORT, C_EXPORT, COM_IMPORT, COM_EXPORT, GOBJECT_IMPORT, GOBJECT_EXPORT,
	REFLECT, PURE, LAZY, NO_ESCAPE, MUST_USE, DERIVE, DEPRECATED,
	TRACKED, OBSERVABLE, MEMOIZED, FOREIGN, FOREIGN_CHANNEL;
}

public class DeclarationPolicyRegistry : Object {
	public const uint VERSION = 1;
	public static DeclarationPolicyId lookup(string spelling) {
		switch (spelling) {
		case "Shared":
			return DeclarationPolicyId.SHARED;
		case "Monitor":
			return DeclarationPolicyId.MONITOR;
		case "Singleton":
			return DeclarationPolicyId.SINGLETON;
		case "ThreadBound":
			return DeclarationPolicyId.THREAD_BOUND;
		case "Actor":
			return DeclarationPolicyId.ACTOR;
		case "Allocator":
			return DeclarationPolicyId.ALLOCATOR;
		case "Align":
			return DeclarationPolicyId.ALIGN;
		case "Repr":
			return DeclarationPolicyId.REPR;
		case "ExceptionRoot":
			return DeclarationPolicyId.EXCEPTION_ROOT;
		case "CCode":
			return DeclarationPolicyId.C_CODE;
		case "FloatingPoint":
			return DeclarationPolicyId.FLOATING_POINT;
		case "Utf8MessageFactory":
			return DeclarationPolicyId.UTF8_MESSAGE_FACTORY;
		case "CallerFilePath":
			return DeclarationPolicyId.CALLER_FILE;
		case "CallerLineNumber":
			return DeclarationPolicyId.CALLER_LINE;
		case "CallerArgumentExpression":
			return DeclarationPolicyId.CALLER_ARGUMENT;
		case "CImport":
			return DeclarationPolicyId.C_IMPORT;
		case "CExport":
			return DeclarationPolicyId.C_EXPORT;
		case "COMImport":
			return DeclarationPolicyId.COM_IMPORT;
		case "COMExport":
			return DeclarationPolicyId.COM_EXPORT;
		case "GObjectImport":
			return DeclarationPolicyId.GOBJECT_IMPORT;
		case "GObjectExport":
			return DeclarationPolicyId.GOBJECT_EXPORT;
		case "Reflect":
			return DeclarationPolicyId.REFLECT;
		case "Pure":
			return DeclarationPolicyId.PURE;
		case "Lazy":
			return DeclarationPolicyId.LAZY;
		case "NoEscape":
			return DeclarationPolicyId.NO_ESCAPE;
		case "MustUse":
			return DeclarationPolicyId.MUST_USE;
		case "Derive":
			return DeclarationPolicyId.DERIVE;
		case "Deprecated":
			return DeclarationPolicyId.DEPRECATED;
		case "Tracked":
			return DeclarationPolicyId.TRACKED;
		case "Observable":
			return DeclarationPolicyId.OBSERVABLE;
		case "Memoized":
			return DeclarationPolicyId.MEMOIZED;
		case "Foreign":
			return DeclarationPolicyId.FOREIGN;
		case "ForeignChannel":
			return DeclarationPolicyId.FOREIGN_CHANNEL;
		default:
			return DeclarationPolicyId.INVALID;
		}
	}
	public static string spelling(DeclarationPolicyId kind) {
		foreach (string name in names ()) {
			if (lookup (name) == kind) {
				return name;
			}
		}
		return "<unknown>";
	}
	public static string[] names() {
		return {
				   "Shared", "Monitor", "Singleton", "ThreadBound", "Actor", "Allocator", "Align", "Repr", "ExceptionRoot", "CCode", "FloatingPoint", "Utf8MessageFactory", "CallerFilePath", "CallerLineNumber", "CallerArgumentExpression", "CImport", "CExport", "COMImport", "COMExport", "GObjectImport", "GObjectExport", "Reflect", "Pure", "Lazy", "NoEscape", "MustUse", "Derive", "Deprecated", "Tracked", "Observable", "Memoized", "Foreign", "ForeignChannel"
		};
	}
	public static bool available(DeclarationPolicyId kind) {
		return kind >= DeclarationPolicyId.SHARED && kind <= DeclarationPolicyId.GOBJECT_EXPORT || kind == DeclarationPolicyId.FOREIGN || kind == DeclarationPolicyId.FOREIGN_CHANNEL;
	}
	public static bool storage(DeclarationPolicyId kind) {
		return kind == DeclarationPolicyId.ALLOCATOR || kind == DeclarationPolicyId.ALIGN || kind == DeclarationPolicyId.REPR;
	}
	public static string placement(DeclarationPolicyId kind) {
		switch (kind) {
		case DeclarationPolicyId.SHARED:
		case DeclarationPolicyId.MONITOR:
			return "class; selected shared interface";
		case DeclarationPolicyId.SINGLETON:
		case DeclarationPolicyId.THREAD_BOUND:
		case DeclarationPolicyId.ACTOR:
		case DeclarationPolicyId.ALLOCATOR:
		case DeclarationPolicyId.EXCEPTION_ROOT:
			return "class";
		case DeclarationPolicyId.ALIGN:
			return "class; C-layout record";
		case DeclarationPolicyId.REPR:
			return "selected scalar POD record";
		case DeclarationPolicyId.C_CODE:
			return "explicit foreign declaration; selected C record export";
		case DeclarationPolicyId.C_IMPORT:
			return "top-level C function import; selected finite ABI";
		case DeclarationPolicyId.C_EXPORT:
			return "nonthrowing function; selected Shared Class opaque adapter";
		case DeclarationPolicyId.COM_EXPORT:
			return "plain Shared Class with explicit CExport; Windows x64 Value/Scale interfaces";
		case DeclarationPolicyId.COM_IMPORT:
			return "global nominal interface; Windows x64 Value or Scale view";
		case DeclarationPolicyId.GOBJECT_EXPORT:
			return "Shared Class with explicit CExport; hosted Linux x64 GType/property/signal";
		case DeclarationPolicyId.GOBJECT_IMPORT:
			return "typed source/VAPI callable at an explicit GObject/GIR C bridge";
		case DeclarationPolicyId.FOREIGN:
			return "explicit declarations-v1 Class constructor/method/property selection";
		case DeclarationPolicyId.FOREIGN_CHANNEL:
			return "actual selected native parameter or result; typed ownership, count, direction and scope facts";
		case DeclarationPolicyId.FLOATING_POINT:
		case DeclarationPolicyId.UTF8_MESSAGE_FACTORY:
			return "native function";
		case DeclarationPolicyId.CALLER_FILE:
		case DeclarationPolicyId.CALLER_LINE:
		case DeclarationPolicyId.CALLER_ARGUMENT:
			return "native parameter";
		default:
			return "unavailable attribute; requires its own implementation contract";
		}
	}
	public static string arguments(DeclarationPolicyId kind) {
		switch (kind) {
		case DeclarationPolicyId.ALLOCATOR:
		case DeclarationPolicyId.ALIGN:
		case DeclarationPolicyId.REPR:
		case DeclarationPolicyId.C_CODE:
		case DeclarationPolicyId.FLOATING_POINT:
			return "named string literals; checked by the policy-specific typed authority";
		case DeclarationPolicyId.CALLER_ARGUMENT:
			return "one string naming an earlier required parameter";
		case DeclarationPolicyId.C_IMPORT:
			return "optional name/header/transport/bool_abi=c99 named strings; checked C ABI";
		case DeclarationPolicyId.C_EXPORT:
			return "function: name/record_abi/bool_abi=c99; Class: explicit name, optional int property";
		case DeclarationPolicyId.COM_EXPORT:
			return "explicit value_iid/scale_iid; threading=constructing";
		case DeclarationPolicyId.COM_IMPORT:
			return "explicit name/iid/view=value|scale/threading=constructing";
		case DeclarationPolicyId.GOBJECT_EXPORT:
			return "explicit type/namespace/version=1.0; matching C prefix and value property";
		case DeclarationPolicyId.GOBJECT_IMPORT:
			return "explicit header and selected C signature; optional name/transport strings";
		case DeclarationPolicyId.FOREIGN:
			return "optional name/personalities; named error_domain/errors mapping and nullable-result null_status; checked native member binding";
		case DeclarationPolicyId.FOREIGN_CHANNEL:
			return "explicit parameter; checked direction/transfer/nullability/encoding/count/scope relationships";
		default:
			return available (kind) ? "none" : "unavailable";
		}
	}
	public static string format() {
		var output = new StringBuilder ("astra-policy-registry/%u\nID\tNAME\tSTATUS\tPLACEMENT\tARGUMENTS\n".printf (VERSION));
		foreach (string name in names ()) {
			var kind = lookup (name);
			output.append ("%u\t%s\t%s\t%s\t%s\n".printf ((uint) kind, name, available (kind) ? "AVAILABLE_SELECTED_PROFILE" : "RESERVED_UNIMPLEMENTED", placement (kind), arguments (kind)));
		}
		return output.str;
	}
}
}
