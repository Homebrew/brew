package org.msgpack.jruby;

import java.util.Arrays;

import org.jruby.Ruby;
import org.jruby.RubyModule;
import org.jruby.RubyClass;
import org.jruby.RubyString;
import org.jruby.RubyObject;
import org.jruby.RubyArray;
import org.jruby.RubyHash;
import org.jruby.RubyNumeric;
import org.jruby.RubyFixnum;
import org.jruby.RubyProc;
import org.jruby.RubyIO;
import org.jruby.exceptions.RaiseException;
import org.jruby.runtime.builtin.IRubyObject;
import org.jruby.runtime.Block;
import org.jruby.runtime.ObjectAllocator;
import org.jruby.runtime.ThreadContext;
import org.jruby.anno.JRubyClass;
import org.jruby.anno.JRubyMethod;
import org.jruby.util.ByteList;

import static org.jruby.runtime.Visibility.PRIVATE;

@JRubyClass(name="MessagePack::Unpacker")
public class Unpacker extends RubyObject {
  private static final long serialVersionUID = 8451264671199362492L;
  private transient final ExtensionRegistry registry;

  private transient IRubyObject stream;
  private transient IRubyObject data;
  private transient Decoder decoder;
  private final RubyClass underflowErrorClass;
  private boolean symbolizeKeys;
  private boolean freeze;
  private boolean allowUnknownExt;

  public Unpacker(Ruby runtime, RubyClass type) {
    this(runtime, type, new ExtensionRegistry());
  }

  public Unpacker(Ruby runtime, RubyClass type, ExtensionRegistry registry) {
    super(runtime, type);
    this.registry = registry;
    this.underflowErrorClass = runtime.getModule("MessagePack").getClass("UnderflowError");
  }

  static class UnpackerAllocator implements ObjectAllocator {
    public IRubyObject allocate(Ruby runtime, RubyClass klass) {
      return new Unpacker(runtime, klass);
    }
  }

  @JRubyMethod(name = "initialize", optional = 2, visibility = PRIVATE)
  public IRubyObject initialize(ThreadContext ctx, IRubyObject[] args) {
    Ruby runtime = ctx.runtime;

    symbolizeKeys = false;
    allowUnknownExt = false;
    freeze = false;

    IRubyObject io = null;
    RubyHash options = null;

    if (args.length >= 1) {
      io = args[0];
    }

    if (args.length >= 2 && args[1] != runtime.getNil()) {
      options = (RubyHash)args[1];
    }

    if (options == null && io != null && io instanceof RubyHash) {
      options = (RubyHash)io;
      io = null;
    }

    if (options != null) {
      IRubyObject sk = options.fastARef(runtime.newSymbol("symbolize_keys"));
      if (sk != null) {
        symbolizeKeys = sk.isTrue();
      }
      IRubyObject f = options.fastARef(runtime.newSymbol("freeze"));
      if (f != null) {
        freeze = f.isTrue();
      }
      IRubyObject au = options.fastARef(runtime.newSymbol("allow_unknown_ext"));
      if (au != null) {
        allowUnknownExt = au.isTrue();
      }

    }

    if (io != null && io != runtime.getNil()) {
      setStream(ctx, io);
    }

    return this;
  }

  public static Unpacker newUnpacker(ThreadContext ctx, ExtensionRegistry extRegistry, IRubyObject[] args) {
    Unpacker unpacker = new Unpacker(ctx.runtime, ctx.runtime.getModule("MessagePack").getClass("Unpacker"), extRegistry);
    unpacker.initialize(ctx, args);
    return unpacker;
  }

  @JRubyMethod(name = "symbolize_keys?")
  public IRubyObject isSymbolizeKeys(ThreadContext ctx) {
    return symbolizeKeys ? ctx.runtime.getTrue() : ctx.runtime.getFalse();
  }

  @JRubyMethod(name = "freeze?")
  public IRubyObject isFreeze(ThreadContext ctx) {
    return freeze ? ctx.runtime.getTrue() : ctx.runtime.getFalse();
  }

  @JRubyMethod(name = "allow_unknown_ext?")
  public IRubyObject isAllowUnknownExt(ThreadContext ctx) {
    return allowUnknownExt ? ctx.runtime.getTrue() : ctx.runtime.getFalse();
  }

  @JRubyMethod(name = "registered_types_internal", visibility = PRIVATE)
  public IRubyObject registeredTypesInternal(ThreadContext ctx) {
    return registry.toInternalUnpackerRegistry(ctx);
  }

  @JRubyMethod(name = "register_type_internal", required = 3, visibility = PRIVATE)
  public IRubyObject registerTypeInternal(ThreadContext ctx, IRubyObject type, IRubyObject mod, IRubyObject proc) {
    testFrozen("MessagePack::Unpacker");

    Ruby runtime = ctx.runtime;

    long typeId = ((RubyFixnum) type).getLongValue();
    if (typeId < -128 || typeId > 127) {
      throw runtime.newRangeError(String.format("integer %d too big to convert to `signed char'", typeId));
    }

    RubyModule extModule = null;
    if (mod != runtime.getNil()) {
      extModule = (RubyModule)mod;
    }

    registry.put(extModule, (int) typeId, false, null, proc);
    return runtime.getNil();
  }

  @JRubyMethod(required = 2)
  public IRubyObject execute(ThreadContext ctx, IRubyObject data, IRubyObject offset) {
    return executeLimit(ctx, data, offset, null);
  }

  @JRubyMethod(name = "execute_limit", required = 3)
  public IRubyObject executeLimit(ThreadContext ctx, IRubyObject str, IRubyObject off, IRubyObject lim) {
    RubyString input = str.asString();
    int offset = RubyNumeric.fix2int(off);
    int limit = lim == null || lim.isNil() ? -1 : RubyNumeric.fix2int(lim);
    ByteList byteList = input.getByteList();
    if (limit == -1) {
      limit = byteList.length() - offset;
    }
    Decoder decoder = new Decoder(ctx.runtime, this, byteList.unsafeBytes(), byteList.begin() + offset, limit, symbolizeKeys, freeze, allowUnknownExt);
    try {
      data = null;
      data = decoder.next();
    } catch (RaiseException re) {
      if (re.getException().getType() != underflowErrorClass) {
        throw re;
      }
    }
    return ctx.runtime.newFixnum(decoder.offset());
  }

  @JRubyMethod(name = "data")
  public IRubyObject getData(ThreadContext ctx) {
    if (data == null) {
      return ctx.runtime.getNil();
    } else {
      return data;
    }
  }

  @JRubyMethod(name = "finished?")
  public IRubyObject finished_p(ThreadContext ctx) {
    return data == null ? ctx.runtime.getFalse() : ctx.runtime.getTrue();
  }

  @JRubyMethod(required = 1, name = "feed", alias = { "feed_reference" })
  public IRubyObject feed(ThreadContext ctx, IRubyObject data) {
    ByteList byteList = data.asString().getByteList();
    if (decoder == null) {
      decoder = new Decoder(ctx.runtime, this, byteList.unsafeBytes(), byteList.begin(), byteList.length(), symbolizeKeys, freeze, allowUnknownExt);
    } else {
      decoder.feed(byteList.unsafeBytes(), byteList.begin(), byteList.length());
    }
    return this;
  }

  @JRubyMethod(name = "full_unpack")
  public IRubyObject fullUnpack(ThreadContext ctx) {
    return decoder.next();
  }

  @JRubyMethod(name = "feed_each", required = 1)
  public IRubyObject feedEach(ThreadContext ctx, IRubyObject data, Block block) {
    feed(ctx, data);
    if (block.isGiven()) {
      each(ctx, block);
      return ctx.runtime.getNil();
    } else {
      return callMethod(ctx, "to_enum");
    }
  }

  @JRubyMethod
  public IRubyObject each(ThreadContext ctx, Block block) {
    if (block.isGiven()) {
      if (decoder != null) {
        try {
          while (decoder.hasNext()) {
            block.yield(ctx, decoder.next());
          }
        } catch (RaiseException re) {
          if (re.getException().getType() != underflowErrorClass) {
            throw re;
          }
        }
      }
      return this;
    } else {
      return callMethod(ctx, "to_enum");
    }
  }

  @JRubyMethod
  public IRubyObject fill(ThreadContext ctx) {
    return ctx.runtime.getNil();
  }

  @JRubyMethod
  public IRubyObject reset(ThreadContext ctx) {
    if (decoder != null) {
      decoder.reset();
    }
    return ctx.runtime.getNil();
  }

  @JRubyMethod(name = "read", alias = { "unpack" })
  public IRubyObject read(ThreadContext ctx) {
    if (decoder == null) {
      throw ctx.runtime.newEOFError();
    }
    try {
      return decoder.next();
    } catch (RaiseException re) {
      if (re.getException().getType() != underflowErrorClass) {
        throw re;
      } else {
        throw ctx.runtime.newEOFError();
      }
    }
  }

  @JRubyMethod(name = "skip")
  public IRubyObject skip(ThreadContext ctx) {
    throw ctx.runtime.newNotImplementedError("Not supported yet in JRuby implementation");
  }

  @JRubyMethod(name = "skip_nil")
  public IRubyObject skipNil(ThreadContext ctx) {
    throw ctx.runtime.newNotImplementedError("Not supported yet in JRuby implementation");
  }

  @JRubyMethod
  public IRubyObject read_array_header(ThreadContext ctx) {
    if (decoder != null) {
      try {
        return decoder.read_array_header();
      } catch (RaiseException re) {
        if (re.getException().getType() != underflowErrorClass) {
          throw re;
        } else {
          throw ctx.runtime.newEOFError();
        }
      }
    }
    return ctx.runtime.getNil();
  }

  @JRubyMethod
  public IRubyObject read_map_header(ThreadContext ctx) {
    if (decoder != null) {
      try {
        return decoder.read_map_header();
      } catch (RaiseException re) {
        if (re.getException().getType() != underflowErrorClass) {
          throw re;
        } else {
          throw ctx.runtime.newEOFError();
        }
      }
    }
    return ctx.runtime.getNil();
  }

  @JRubyMethod(name = "stream")
  public IRubyObject getStream(ThreadContext ctx) {
    if (stream == null) {
      return ctx.runtime.getNil();
    } else {
      return stream;
    }
  }

  @JRubyMethod(name = "stream=", required = 1)
  public IRubyObject setStream(ThreadContext ctx, IRubyObject stream) {
    RubyString str;
    if (stream instanceof RubyIO) {
      str = stream.callMethod(ctx, "read").asString();
    } else if (stream.respondsTo("read")) {
      str = stream.callMethod(ctx, "read").asString();
    } else {
      throw ctx.runtime.newTypeError(stream, "IO");
    }
    ByteList byteList = str.getByteList();
    this.stream = stream;
    this.decoder = null;
    this.decoder = new Decoder(ctx.runtime, this, byteList.unsafeBytes(), byteList.begin(), byteList.length(), symbolizeKeys, freeze, allowUnknownExt);
    return getStream(ctx);
  }

  public ExtensionRegistry.ExtensionEntry lookupExtensionByTypeId(int typeId) {
    return registry.lookupExtensionByTypeId(typeId);
  }
}
