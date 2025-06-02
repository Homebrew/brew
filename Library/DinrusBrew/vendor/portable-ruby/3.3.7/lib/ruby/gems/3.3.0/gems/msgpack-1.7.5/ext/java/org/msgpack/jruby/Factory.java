package org.msgpack.jruby;


import org.jruby.Ruby;
import org.jruby.RubyModule;
import org.jruby.RubyClass;
import org.jruby.RubyObject;
import org.jruby.RubyArray;
import org.jruby.RubyHash;
import org.jruby.RubyIO;
import org.jruby.RubyInteger;
import org.jruby.RubyFixnum;
import org.jruby.RubyString;
import org.jruby.RubySymbol;
import org.jruby.RubyProc;
import org.jruby.RubyMethod;
import org.jruby.runtime.builtin.IRubyObject;
import org.jruby.anno.JRubyClass;
import org.jruby.anno.JRubyMethod;
import org.jruby.runtime.ThreadContext;
import org.jruby.runtime.ObjectAllocator;
import org.jruby.util.ByteList;

import static org.jruby.runtime.Visibility.PRIVATE;

@JRubyClass(name="MessagePack::Factory")
public class Factory extends RubyObject {
  private static final long serialVersionUID = 8441284623445322492L;
  private transient final Ruby runtime;
  private transient ExtensionRegistry extensionRegistry;
  private boolean hasSymbolExtType;
  private boolean hasBigIntExtType;

  public Factory(Ruby runtime, RubyClass type) {
    super(runtime, type);
    this.runtime = runtime;
    this.extensionRegistry = new ExtensionRegistry();
    this.hasSymbolExtType = false;
    this.hasBigIntExtType = false;
  }

  static class FactoryAllocator implements ObjectAllocator {
    public IRubyObject allocate(Ruby runtime, RubyClass type) {
      return new Factory(runtime, type);
    }
  }

  public ExtensionRegistry extensionRegistry() {
    return extensionRegistry.dup();
  }

  @JRubyMethod(name = "initialize")
  public IRubyObject initialize(ThreadContext ctx) {
    return this;
  }

  @JRubyMethod(name = "dup")
  public IRubyObject dup() {
    Factory clone = (Factory)super.dup();
    clone.extensionRegistry = extensionRegistry();
    clone.hasSymbolExtType = hasSymbolExtType;
    return clone;
  }

  @JRubyMethod(name = "packer", optional = 2)
  public Packer packer(ThreadContext ctx, IRubyObject[] args) {
    return Packer.newPacker(ctx, extensionRegistry(), hasSymbolExtType, hasBigIntExtType, args);
  }

  @JRubyMethod(name = "unpacker", optional = 2)
  public Unpacker unpacker(ThreadContext ctx, IRubyObject[] args) {
    return Unpacker.newUnpacker(ctx, extensionRegistry(), args);
  }

  @JRubyMethod(name = "registered_types_internal", visibility = PRIVATE)
  public IRubyObject registeredTypesInternal(ThreadContext ctx) {
    return RubyArray.newArray(ctx.runtime, new IRubyObject[] {
      extensionRegistry.toInternalPackerRegistry(ctx),
      extensionRegistry.toInternalUnpackerRegistry(ctx)
    });
  }

  @JRubyMethod(name = "register_type_internal", required = 3, visibility = PRIVATE)
  public IRubyObject registerTypeInternal(ThreadContext ctx, IRubyObject type, IRubyObject mod, IRubyObject opts) {
    testFrozen("MessagePack::Factory");

    Ruby runtime = ctx.runtime;
    RubyHash options = (RubyHash) opts;

    IRubyObject packerProc = options.fastARef(runtime.newSymbol("packer"));
    IRubyObject unpackerProc = options.fastARef(runtime.newSymbol("unpacker"));

    long typeId = ((RubyFixnum) type).getLongValue();
    if (typeId < -128 || typeId > 127) {
      throw runtime.newRangeError(String.format("integer %d too big to convert to `signed char'", typeId));
    }

    if (!(mod instanceof RubyModule)) {
      throw runtime.newArgumentError(String.format("expected Module/Class but found %s.", mod.getType().getName()));
    }
    RubyModule extModule = (RubyModule) mod;

    boolean recursive = false;
    if (options != null) {
      IRubyObject recursiveExtensionArg = options.fastARef(runtime.newSymbol("recursive"));
      if (recursiveExtensionArg != null && recursiveExtensionArg.isTrue()) {
        recursive = true;
      }
    }

    extensionRegistry.put(extModule, (int) typeId, recursive, packerProc, unpackerProc);

    if (extModule == runtime.getSymbol() && !packerProc.isNil()) {
      hasSymbolExtType = true;
    }

    if (options != null) {
      IRubyObject oversizedIntegerExtensionArg = options.fastARef(runtime.newSymbol("oversized_integer_extension"));
      if (oversizedIntegerExtensionArg != null && oversizedIntegerExtensionArg.isTrue()) {
        if (extModule == runtime.getModule("Integer")) {
          hasBigIntExtType = true;
        } else {
          throw runtime.newArgumentError("oversized_integer_extension: true is only for Integer class");
        }
      }
    }

    return runtime.getNil();
  }
}
