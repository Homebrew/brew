# typed: strict
# frozen_string_literal: true

require "resource"
require "erb"
require "utils/output"

Owner = T.type_alias { T.any(Formula, Resource, SoftwareSpec) }

# Helper module for creating patches.
module Patch
  sig {
    params(
      strip: T.any(Symbol, String),
      src:   T.nilable(T.any(Symbol, String)),
      block: T.nilable(T.proc.bind(Resource::Patch).void),
    ).returns(T.any(EmbeddedPatch, ExternalPatch))
  }
  def self.create(strip, src, &block)
    case strip
    when :DATA
      DATAPatch.new(:p1)
    when String
      StringPatch.new(:p1, strip)
    when Symbol
      case src
      when :DATA
        DATAPatch.new(strip)
      when String
        StringPatch.new(strip, src)
      else
        ExternalPatch.new(strip, &block)
      end
    end
  end
end

# An abstract class representing a patch embedded into a formula.
class EmbeddedPatch
  include Utils::Output::Mixin
  extend T::Helpers

  abstract!

  sig { params(owner: T.nilable(Owner)).returns(T.nilable(Owner)) }
  attr_writer :owner

  sig { returns(T.any(String, Symbol)) }
  attr_reader :strip

  sig { params(strip: T.any(String, Symbol)).void }
  def initialize(strip)
    @strip = T.let(strip, T.any(String, Symbol))
    @owner = T.let(nil, T.nilable(Owner))
  end

  sig { returns(T::Boolean) }
  def external?
    false
  end

  sig { abstract.returns(String) }
  def contents; end

  sig { void }
  def apply
    data = contents.gsub("@@HOMEBREW_PREFIX@@", HOMEBREW_PREFIX)
    if data.gsub!("HOMEBREW_PREFIX", HOMEBREW_PREFIX)
      odeprecated "patch with HOMEBREW_PREFIX placeholder",
                  "patch with @@HOMEBREW_PREFIX@@ placeholder"
    end
    args = %W[-g 0 -f -#{strip}]
    Utils.safe_popen_write("patch", *args) { |p| p.write(data) }
  end

  sig { returns(String) }
  def inspect
    "#<#{self.class.name}: #{strip.inspect}>"
  end
end

# A patch at the `__END__` of a formula file.
class DATAPatch < EmbeddedPatch
  sig { returns(T.nilable(Pathname)) }
  attr_accessor :path

  sig { params(strip: T.any(String, Symbol)).void }
  def initialize(strip)
    super
    @path = T.let(nil, T.nilable(Pathname))
  end

  sig { override.returns(String) }
  def contents
    path = self.path
    raise ArgumentError, "DATAPatch#contents called before path was set!" unless path

    data = +""
    path.open("rb") do |f|
      loop do
        line = f.gets
        break if line.nil? || /^__END__$/.match?(line)
      end
      while (line = f.gets)
        data << line
      end
    end
    data.freeze
  end
end

# A string containing a patch.
class StringPatch < EmbeddedPatch
  sig { params(strip: T.any(String, Symbol), str: String).void }
  def initialize(strip, str)
    super(strip)
    @str = T.let(str, String)
  end

  sig { override.returns(String) }
  def contents
    @str
  end
end

# A file containing a patch.
class ExternalPatch
  include Utils::Output::Mixin

  extend Forwardable

  sig { returns(Resource::Patch) }
  attr_reader :resource

  sig { returns(T.any(String, Symbol)) }
  attr_reader :strip

  def_delegators :resource,
                 :url, :fetch, :patch_files, :verify_download_integrity,
                 :cached_download, :downloaded?, :clear_cache

  sig { params(strip: T.any(String, Symbol), block: T.nilable(T.proc.bind(Resource::Patch).void)).void }
  def initialize(strip, &block)
    @strip    = T.let(strip, T.any(String, Symbol))
    @resource = T.let(Resource::Patch.new(&block), Resource::Patch)
  end

  sig { returns(T::Boolean) }
  def external?
    true
  end

  sig { params(owner: T.nilable(Owner)).void }
  def owner=(owner)
    resource.owner = owner
    resource.version(resource.checksum&.hexdigest || ERB::Util.url_encode(resource.url))
  end

  sig { void }
  def apply
    base_dir = Pathname.pwd
    resource.unpack do
      patch_dir = Pathname.pwd
      if patch_files.empty?
        children = patch_dir.children
        if children.length != 1 || !children.fetch(0).file?
          raise MissingApplyError, <<~EOS
            There should be exactly one patch file in the staging directory unless
            the "apply" method was used one or more times in the patch-do block.
          EOS
        end

        patch_files << children.fetch(0).basename
      end
      dir = base_dir
      dir /= resource.directory if resource.directory.present?
      dir.cd do
        patch_files.each do |patch_file|
          ohai "Applying #{patch_file}"
          patch_file = patch_dir/patch_file
          Utils.safe_popen_write("patch", "-g", "0", "-f", "-#{strip}") do |p|
            File.foreach(patch_file) do |line|
              data = line.gsub("@@HOMEBREW_PREFIX@@", HOMEBREW_PREFIX)
              p.write(data)
            end
          end
        end
      end
    end
  rescue ErrorDuringExecution => e
    onoe e
    f = resource.owner.owner
    cmd, *args = e.cmd
    raise BuildError.new(f, cmd, args, ENV.to_hash)
  end

  sig { returns(String) }
  def inspect
    "#<#{self.class.name}: #{strip.inspect} #{url.inspect}>"
  end
end
