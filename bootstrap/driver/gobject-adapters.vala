// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Semantic;

namespace Astra.Driver {
public class GObjectAdapters : Object {
	public static string generate(CheckedProgram program, bool implementation) throws ForeignAdapterError {
		string declared = GObjectImports.generate (program, implementation) + GObjectDeclared.generate (program, implementation);
		if (implementation && declared != "") {
			declared = ForeignAdapters.source (program) + declared;
		}
		var identities = new StringBuilder ();
		foreach (var owner in program.classes) {
			if (owner.foreign_export != null && owner.foreign_export.gobject != null && owner.foreign_export.declared_api == null) {
				identities.append (owner.foreign_export.identity ());
				identities.append_c ('\n');
			}
		}
		if (identities.len == 0 && declared != "") {
			return declared;
		}
		if (identities.len == 0) {
			throw new ForeignAdapterError.INVALID ("no checked GObject Class exports were selected");
		}
		string guard = "ASTRA_GOBJECT_V1_" + Checksum.compute_for_string (ChecksumType.SHA256, identities.str).up ();
		var text = new StringBuilder ("/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */\n");
		if (implementation) {
			text.append ("#define ASTRA_FOREIGN14_INTERNAL\n" + ForeignAdapters.header (program));
		}
		text.append ("\n#ifndef " + guard + "\n#define " + guard + "\n#include <glib-object.h>\nG_BEGIN_DECLS\n");
		foreach (var owner in program.classes) {
			var policy = owner.foreign_export;
			if (policy == null || policy.gobject == null || policy.declared_api != null) {
				continue;
			}
			if (!ForeignClassPolicy.matches (policy, ((ClassType) owner.semantic_type).foreign_policy_identity, owner.name)) {
				throw new ForeignAdapterError.INVALID ("GObject generator lost its checked native root/property/affinity/cache identity");
			}
			var contract = policy.gobject;
			string p = policy.prefix;
			string t = contract.type_name;
			string space = contract.namespace_name.up ();
			string local = t.substring (contract.namespace_name.length).up ();
			text.append_printf ("\n/* %s */\n#define %s_TYPE_%s (%s_get_type())\nG_DECLARE_FINAL_TYPE(%s, %s, %s, %s, GObject)\n/**\n * %sHandle: (skip)\n */\ntypedef struct %s_handle %sHandle;\n/**\n * %s::changed:\n * @self: the native-backed object\n * @value: the new native integer value\n */\n", contract.identity (), space, local, p, t, p, space, local, t, p, t, t);
			text.append_printf ("/**\n * %s_new:\n * @value: initial native value\n * @error: return location for an error\n * Returns: (transfer full) (nullable): a non-floating native-backed object\n */\n%s *%s_new(gint value, GError **error);\n", p, t, p);
			text.append_printf ("/**\n * %s_as_gobject: (skip)\n * @self: a backed opaque native C owner\n * @error: return location for an error\n * Returns: (transfer full) (nullable): the cached live GObject view\n */\n%s *%s_as_gobject(%sHandle *self, GError **error);\n", p, t, p, t);
			text.append_printf ("/**\n * %s_try_get_value:\n * @self: the object\n * @value: (out): copied integer result, cleared on error\n * @error: return location for an error\n * Returns: whether the read succeeded in its constructing context\n */\ngboolean %s_try_get_value(%s *self, gint *value, GError **error);\n", p, p, t);
			text.append_printf ("/**\n * %s_try_set_value:\n * @self: the object\n * @value: copied integer value\n * @error: return location for an error\n * Returns: whether the change succeeded in its constructing context\n */\ngboolean %s_try_set_value(%s *self, gint value, GError **error);\nGQuark %s_error_quark(void);\n", p, p, t, p);
		}
		text.append ("\nG_END_DECLS\n#endif\n");
		if (!implementation) {
			return declared + text.str;
		}
		text.append ("\n#include <stdint.h>\n_Static_assert(sizeof(void *) == 8 && sizeof(gint) == 4, \"selected GObject profile requires Linux x64 and 32-bit gint\");\n");
		foreach (var owner in program.classes) {
			var policy = owner.foreign_export;
			if (policy == null || policy.gobject == null || policy.declared_api != null) {
				continue;
			}
			var contract = policy.gobject;
			string p = policy.prefix;
			string t = contract.type_name;
			text.append ("""
typedef struct { GWeakRef wrapper; gint state; } @P@_Cache;
struct _@T@ { GObject parent_instance; GRecMutex gate; @P@_handle *root; @P@_Cache *cache; gboolean disposed; };
G_DEFINE_TYPE(@T@, @P@, G_TYPE_OBJECT)
static GParamSpec *@P@_value_spec;
static guint @P@_changed;
static _Thread_local @P@_handle *@P@_building_root;
GQuark @P@_error_quark(void) { return g_quark_from_static_string("@P@-error"); }
static gboolean @P@_error(GError **error, gint code, const char *message) {
	g_set_error_literal(error, @P@_error_quark(), code, message); return FALSE;
}
static gboolean @P@_status(int32_t status, GError **error) {
	if (status == 0) return TRUE;
	return @P@_error(error, (uint32_t)status == UINT32_C(0x8001010e) ? 2 : 1,
		(uint32_t)status == UINT32_C(0x8001010e) ? "native data call requires its constructing thread" : "invalid native handle or out slot");
}
static void @P@_cache_retire(void *context) {
	@P@_Cache *cache = context; g_weak_ref_clear(&cache->wrapper); g_free(cache);
}
static @P@_Cache *@P@_cache(@P@_handle *root, GError **error) {
	@P@_Cache *cache = astra_foreign14_@P@_personality(root);
	if (cache) return cache;
	cache = g_try_new0(@P@_Cache, 1);
	if (!cache) { @P@_error(error, 4, "foreign cache allocation failed"); return NULL; }
	g_weak_ref_init(&cache->wrapper, NULL);
	if (!@P@_status(astra_foreign14_@P@_attach(root, cache, @P@_cache_retire), error)) { @P@_cache_retire(cache); return NULL; }
	return cache;
}
static gboolean @P@_admit(@T@ *self, GError **error) {
	if (self->disposed) return @P@_error(error, 3, "GObject view is disposed");
	return @P@_status(astra_foreign14_@P@_check_thread(self->root), error);
}
gboolean @P@_try_get_value(@T@ *self, gint *value, GError **error) {
	if (value) *value = 0;
	if (!self || !value) return @P@_error(error, 1, "object and out slot are required");
	g_object_ref(self); g_rec_mutex_lock(&self->gate);
	gboolean ok = @P@_admit(self, error) && @P@_status(@P@_get(self->root, value), error);
	g_rec_mutex_unlock(&self->gate); g_object_unref(self); return ok;
}
gboolean @P@_try_set_value(@T@ *self, gint value, GError **error) {
	if (!self) return @P@_error(error, 1, "object is required");
	g_object_ref(self); g_rec_mutex_lock(&self->gate);
	gint previous = 0;
	gboolean ok = @P@_admit(self, error) && @P@_status(@P@_get(self->root, &previous), error);
	if (ok) {
		ok = @P@_status(@P@_set(self->root, value), error);
		gint current = previous;
		if (ok && !self->disposed) ok = @P@_status(@P@_get(self->root, &current), error);
		if (ok && !self->disposed && current != previous) {
			g_signal_emit(self, @P@_changed, 0, current);
			if (!self->disposed) g_object_notify_by_pspec(G_OBJECT(self), @P@_value_spec);
		}
	}
	g_rec_mutex_unlock(&self->gate); g_object_unref(self); return ok;
}
static void @P@_get_property(GObject *object, guint id, GValue *value, GParamSpec *spec) {
	if (id == 1) { gint result = 0; @P@_try_get_value((@T@ *)object, &result, NULL); g_value_set_int(value, result); }
	else G_OBJECT_WARN_INVALID_PROPERTY_ID(object, id, spec);
}
static void @P@_set_property(GObject *object, guint id, const GValue *value, GParamSpec *spec) {
	if (id == 1) @P@_try_set_value((@T@ *)object, g_value_get_int(value), NULL);
	else G_OBJECT_WARN_INVALID_PROPERTY_ID(object, id, spec);
}
static void @P@_dispose(GObject *object) {
	@T@ *self = (@T@ *)object;
	g_rec_mutex_lock(&self->gate); self->disposed = TRUE;
	if (self->cache) g_atomic_int_set(&self->cache->state, 2);
	G_OBJECT_CLASS(@P@_parent_class)->dispose(object);
	g_rec_mutex_unlock(&self->gate);
}
static void @P@_finalize(GObject *object) {
	@T@ *self = (@T@ *)object; @P@_handle *root = self->root;
	self->root = NULL;
	if (self->cache) g_atomic_int_set(&self->cache->state, 0);
	self->cache = NULL;
	@P@_release(root); g_rec_mutex_clear(&self->gate);
	G_OBJECT_CLASS(@P@_parent_class)->finalize(object);
}
static void @P@_class_init(@T@Class *klass) {
	GObjectClass *base = G_OBJECT_CLASS(klass);
	base->get_property = @P@_get_property; base->set_property = @P@_set_property;
	base->dispose = @P@_dispose; base->finalize = @P@_finalize;
	@P@_value_spec = g_param_spec_int("value", "Value", "Native integer value", G_MININT, G_MAXINT, 0, G_PARAM_READWRITE | G_PARAM_EXPLICIT_NOTIFY | G_PARAM_STATIC_STRINGS);
	g_object_class_install_property(base, 1, @P@_value_spec);
	/**
	 * @T@::changed:
	 * @self: the native-backed object
	 * @value: the new native integer value
	 */
	@P@_changed = g_signal_new("changed", G_TYPE_FROM_CLASS(klass), G_SIGNAL_RUN_LAST, 0, NULL, NULL, g_cclosure_marshal_VOID__INT, G_TYPE_NONE, 1, G_TYPE_INT);
}
static void @P@_init(@T@ *self) {
	g_rec_mutex_init(&self->gate);
	@P@_handle *root = @P@_building_root; @P@_building_root = NULL;
	if (root) @P@_acquire(root); else root = @P@_create(0);
	if (!root) g_error("native default GObject construction failed");
	self->root = root; self->cache = @P@_cache(root, NULL);
	if (!self->cache) g_error("native GObject cache construction failed");
	g_weak_ref_set(&self->cache->wrapper, self); g_atomic_int_set(&self->cache->state, 1);
}
@T@ *@P@_as_gobject(@P@_handle *root, GError **error) {
	if (!@P@_status(astra_foreign14_@P@_check_thread(root), error)) return NULL;
	@P@_Cache *cache = @P@_cache(root, error); if (!cache) return NULL;
	@T@ *view = g_weak_ref_get(&cache->wrapper);
	if (view) {
		if (g_atomic_int_get(&cache->state) == 1) return view;
		g_object_unref(view); @P@_error(error, 3, "cached GObject view is disposing"); return NULL;
	}
	if (g_atomic_int_get(&cache->state) != 0) { @P@_error(error, 3, "cached GObject view has not finalized"); return NULL; }
	/* Finish class initialization before publishing the construction-local seed. */
	gpointer klass = g_type_class_ref(@P@_get_type());
	if (@P@_building_root) g_error("nested native GObject construction seed");
	@P@_building_root = root;
	view = g_object_new(@P@_get_type(), NULL);
	if (@P@_building_root) g_error("native GObject construction did not consume its seed");
	g_type_class_unref(klass); return view;
}
@T@ *@P@_new(gint value, GError **error) {
	@P@_handle *root = @P@_create(value);
	if (!root) { @P@_error(error, 4, "native root construction failed"); return NULL; }
	@T@ *view = @P@_as_gobject(root, error); @P@_release(root); return view;
}
""".replace ("@P@", p).replace ("@T@", t));
		}
		return declared + text.str;
	}

}
}
