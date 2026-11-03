// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;

namespace Astra.Syntax {
public class SyntaxProgramResult : Object {
	public SyntaxProgram? program { get; private set; }
	public Diagnostic? diagnostic { get; private set; }
	internal SyntaxProgramResult (SyntaxProgram? program, Diagnostic? diagnostic) {
		assert ((program == null) != (diagnostic == null));
		this.program = program;
		this.diagnostic = diagnostic;
	}

}

// Each unit is an independently parsed tree. Declaration arrays are views of
// those original nodes, not a synthetic file or a replacement syntax tree.
public class SyntaxProgram : Object {
	public GenericArray<ClassDeclarationSyntax> c_classes { get; private set; default = new GenericArray<ClassDeclarationSyntax> (); }
	public GenericArray<ComImportSyntax> com_interfaces { get; private set; default = new GenericArray<ComImportSyntax> (); }
	public GenericArray<AsyncRuntimeSyntax> async_runtimes { get; private set; default = new GenericArray<AsyncRuntimeSyntax> (); }
	public GenericArray<EnumDeclarationSyntax> enums { get; private set; default = new GenericArray<EnumDeclarationSyntax> (); }
	public GenericArray<ConstantDeclarationSyntax> constants { get; private set; default = new GenericArray<ConstantDeclarationSyntax> (); }
	public SourceSet sources { get; private set; }
	public GenericArray<CompilationUnitSyntax> units { get; private set; default = new GenericArray<CompilationUnitSyntax> (); }
	public GenericArray<FunctionDeclarationSyntax> functions { get; private set; default = new GenericArray<FunctionDeclarationSyntax> (); }
	public GenericArray<StructDeclarationSyntax> structs { get; private set; default = new GenericArray<StructDeclarationSyntax> (); }
	// The first unit supplies only a fallback diagnostic anchor, never a span
	// covering several physical files. Declarations retain their own spans.
	public SourceSpan span { get { return units[0].span; } }

	public SyntaxProgram (GenericArray<CompilationUnitSyntax> units) throws SourceSetError {
		var files = new GenericArray<SourceFile> ();
		var ordered = new GLib.List<CompilationUnitSyntax> ();
		foreach (var unit in units) {
			files.add (unit.span.file);
			ordered.append (unit);
		}
		sources = new SourceSet (files);
		ordered.sort ((a, b) => strcmp (a.span.file.path, b.span.file.path));
		foreach (var unit in ordered) {
			this.units.add (unit);
		}
		foreach (var unit in this.units) {
			foreach (var contract in unit.c_classes) {
				c_classes.add (contract);
			}
			foreach (var contract in unit.com_interfaces) {
				com_interfaces.add (contract);
			}
			foreach (var runtime in unit.async_runtimes) {
				async_runtimes.add (runtime);
			}
			foreach (var declaration in unit.enums) {
				enums.add (declaration);
			}
			foreach (var constant in unit.constants) {
				constants.add (constant);
			}
			foreach (var function in unit.functions) {
				functions.add (function);
			}
			foreach (var structure in unit.structs) {
				structs.add (structure);
			}
		}
	}

	public GenericArray<NativeInstanceDeclarationSyntax> native_instances(bool include_generic = true) {
		var result = new GenericArray<NativeInstanceDeclarationSyntax> ();
		// Preserve the existing per-kind queues, including single-file ordinals.
		foreach (var structure in structs) {
			if (include_generic || structure.type_parameters.length == 0) {
				result.add (structure);
			}
		}
		foreach (var unit in units) {
			foreach (var instance in unit.classes) {
				if (include_generic || instance.type_parameters.length == 0) {
					result.add (instance);
				}
			}
		}
		return result;
	}

	public static SyntaxProgramResult parse(SourceSet sources) {
		var units = new GenericArray<CompilationUnitSyntax> ();
		foreach (var file in sources.files) {
			var parsed = Parser.parse (file);
			if (parsed.diagnostic != null) {
				return new SyntaxProgramResult (null, parsed.diagnostic);
			}
			units.add (parsed.unit);
		}
		try {
			return new SyntaxProgramResult (new SyntaxProgram (units), null);
		} catch (SourceSetError error) {
			GLib.error ("validated source set: %s", error.message);
		}
	}

}
}
