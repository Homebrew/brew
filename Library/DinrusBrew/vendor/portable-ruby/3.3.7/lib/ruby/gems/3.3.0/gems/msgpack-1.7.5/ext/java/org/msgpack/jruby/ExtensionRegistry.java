package org.msgpack.jruby;

import org.jruby.Ruby;
import org.jruby.RubyHash;
import org.jruby.RubyArray;
import org.jruby.RubyModule;
import org.jruby.RubyFixnum;
import org.jruby.RubySymbol;
import org.jruby.runtime.ThreadContext;
import org.jruby.runtime.builtin.IRubyObject;

import java.util.Map;
import java.util.HashMap;

public class ExtensionRegistry {
  private final Map<RubyModule, ExtensionEntry> extensionsByModule;
  private final Map<RubyModule, ExtensionEntry> extensionsByAncestor;
  private final ExtensionEntry[] extensionsByTypeId;

  public ExtensionRegistry() {
    this(new HashMap<RubyModule, ExtensionEntry>(), new ExtensionEntry[256]);
  }

  private ExtensionRegistry(Map<RubyModule, ExtensionEntry> extensionsByModule, ExtensionEntry[] extensionsByTypeId) {
    this.extensionsByModule = new HashMap<RubyModule, ExtensionEntry>(extensionsByModule);
    this.extensionsByAncestor = new HashMap<RubyModule, ExtensionEntry>();
    this.extensionsByTypeId = extensionsByTypeId.clone();
  }

  public ExtensionRegistry dup() {
    return new ExtensionRegistry(extensionsByModule, extensionsByTypeId);
  }

  public IRubyObject toInternalPackerRegistry(ThreadContext ctx) {
    RubyHash hash = RubyHash.newHash(ctx.runtime);
    for (RubyModule extensionModule : extensionsByModule.keySet()) {
      ExtensionEntry entry = extensionsByModule.get(extensionModule);
      if (entry.hasPacker()) {
        hash.put(extensionModule, entry.toPackerTuple(ctx));
      }
    }
    return hash;
  }

  public IRubyObject toInternalUnpackerRegistry(ThreadContext ctx) {
    RubyHash hash = RubyHash.newHash(ctx.runtime);
    for (int typeIdIndex = 0 ; typeIdIndex < 256 ; typeIdIndex++) {
      ExtensionEntry entry = extensionsByTypeId[typeIdIndex];
      if (entry != null && entry.hasUnpacker()) {
        IRubyObject typeId = RubyFixnum.newFixnum(ctx.runtime, typeIdIndex - 128);
        hash.put(typeId, entry.toUnpackerTuple(ctx));
      }
    }
    return hash;
  }

  public void put(RubyModule mod, int typeId, boolean recursive, IRubyObject packerProc, IRubyObject unpackerProc) {
    ExtensionEntry entry = new ExtensionEntry(mod, typeId, recursive, packerProc, unpackerProc);
    extensionsByModule.put(mod, entry);
    extensionsByTypeId[typeId + 128] = entry;
    extensionsByAncestor.clear();
  }

  public ExtensionEntry lookupExtensionByTypeId(int typeId) {
    ExtensionEntry e = extensionsByTypeId[typeId + 128];
    if (e != null && e.hasUnpacker()) {
      return e;
    }
    return null;
  }

  public ExtensionEntry lookupExtensionForObject(IRubyObject object) {
    RubyModule lookupClass = null;
    ExtensionEntry entry = null;
    /*
     * Objects of type Integer (Fixnum, Bignum), Float, Symbol and frozen
     * String have no singleton class and raise a TypeError when trying to get
     * it.
     */
    lookupClass = object.getMetaClass();
    entry = extensionsByModule.get(lookupClass);
    if (entry != null && entry.hasPacker()) {
      return entry;
    }

    RubyModule realClass = object.getType();
    if (realClass != lookupClass) {
      entry = extensionsByModule.get(realClass);
      if (entry != null && entry.hasPacker()) {
        return entry;
      }
    }

    entry = findEntryByModuleOrAncestor(lookupClass);
    if (entry != null && entry.hasPacker()) {
      return entry;
    }
    return null;
  }

  private ExtensionEntry findEntryByModuleOrAncestor(final RubyModule mod) {
    ThreadContext ctx = mod.getRuntime().getCurrentContext();
    for (RubyModule extensionModule : extensionsByModule.keySet()) {
      RubyArray<?> ancestors = (RubyArray)mod.callMethod(ctx, "ancestors");
      if (ancestors.callMethod(ctx, "include?", extensionModule).isTrue()) {
        return extensionsByModule.get(extensionModule);
      }
    }
    return null;
  }

  public static class ExtensionEntry {
    private final RubyModule mod;
    private final int typeId;
    private final boolean recursive;
    private final IRubyObject packerProc;
    private final IRubyObject unpackerProc;

    public ExtensionEntry(RubyModule mod, int typeId, boolean recursive, IRubyObject packerProc, IRubyObject unpackerProc) {
      this.mod = mod;
      this.typeId = typeId;
      this.recursive = recursive;
      this.packerProc = packerProc;
      this.unpackerProc = unpackerProc;
    }

    public RubyModule getExtensionModule() {
      return mod;
    }

    public int getTypeId() {
      return typeId;
    }

    public boolean isRecursive() {
      return recursive;
    }

    public boolean hasPacker() {
      return packerProc != null && !packerProc.isNil();
    }

    public boolean hasUnpacker() {
      return unpackerProc != null && !unpackerProc.isNil();
    }

    public IRubyObject getPackerProc() {
      return packerProc;
    }

    public IRubyObject getUnpackerProc() {
      return unpackerProc;
    }

    public RubyArray<?> toPackerTuple(ThreadContext ctx) {
      return ctx.runtime.newArray(new IRubyObject[] {ctx.runtime.newFixnum(typeId), packerProc});
    }

    public RubyArray<?> toUnpackerTuple(ThreadContext ctx) {
      return ctx.runtime.newArray(new IRubyObject[] {mod, unpackerProc});
    }

    public IRubyObject[] toPackerProcTypeIdPair(ThreadContext ctx) {
      return new IRubyObject[] {packerProc, ctx.runtime.newFixnum(typeId)};
    }
  }
}
