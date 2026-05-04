# typed: strict
# frozen_string_literal: true

require "resource"
require "erb"
require "utils/output"

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
        resource = Resource::Patch.new(&block)
        if (file = resource.file)
          raise ArgumentError, "Patch cannot have both `file` and `url`." if resource.url.present?

          LocalPatch.new(strip, file)
        else
          ExternalPatch.new(strip, resource)
        end
      end
    end
  end
end

# An abstract class representing a patch embedded into a formula.
class EmbeddedPatch # rubocop:todo Style/OneClassPerFile
  include Utils::Output::Mixin
  extend T::Helpers

  abstract!

  sig { returns(T.nilable(Resource::Owner)) }
  attr_accessor :owner

  sig { returns(T.any(String, Symbol)) }
  attr_reader :strip

  sig { params(strip: T.any(String, Symbol)).void }
  def initialize(strip)
    @strip = strip
    @owner = T.let(nil, T.nilable(Resource::Owner))
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
      odisabled "patch with HOMEBREW_PREFIX placeholder",
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
class DATAPatch < EmbeddedPatch # rubocop:todo Style/OneClassPerFile
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
class StringPatch < EmbeddedPatch # rubocop:todo Style/OneClassPerFile
  sig { params(strip: T.any(String, Symbol), str: String).void }
  def initialize(strip, str)
    super(strip)
    @str = str
  end

  sig { override.returns(String) }
  def contents
    @str
  end
end

# A patch file stored in the same repository as its formula.
class LocalPatch < EmbeddedPatch # rubocop:todo Style/OneClassPerFile
  sig { returns(T.any(String, Pathname)) }
  attr_reader :file

  sig { params(strip: T.any(String, Symbol), file: T.any(String, Pathname)).void }
  def initialize(strip, file)
    super(strip)
    @file = file
  end

  sig { override.returns(String) }
  def contents
    owner = self.owner
    raise ArgumentError, "LocalPatch#contents called before owner was set!" unless owner

    formula = T.cast(owner, SoftwareSpec).owner
    raise ArgumentError, "LocalPatch#contents requires a formula owner!" unless formula.is_a?(::Formula)

    repository_path = formula.tap&.path || formula.path.dirname
    file_path = repository_path/Pathname(file)
    repository_realpath = repository_path.realpath
    file_realpath = file_path.realpath
    unless file_realpath.to_s.start_with?("#{repository_realpath}/")
      raise ArgumentError, "Patch file must be within the formula repository."
    end

    file_realpath.read
  end

  sig { override.returns(String) }
  def inspect
    "#<#{self.class.name}: #{strip.inspect} #{file.inspect}>"
  end
end

# A file containing a patch.
class ExternalPatch # rubocop:todo Style/OneClassPerFile
  include Utils::Output::Mixin

  extend Forwardable

  sig { returns(Resource::Patch) }
  attr_reader :resource

  sig { returns(T.any(String, Symbol)) }
  attr_reader :strip

  def_delegators :resource,
                 :url, :fetch, :patch_files, :verify_download_integrity,
                 :cached_download, :downloaded?, :clear_cache

  sig {
    params(
      strip:    T.any(String, Symbol),
      resource: T.nilable(Resource::Patch),
      block:    T.nilable(T.proc.bind(Resource::Patch).void),
    ).void
  }
  def initialize(strip, resource = nil, &block)
    @strip    = strip
    @resource = T.let(resource || Resource::Patch.new(&block), Resource::Patch)
  end

  sig { returns(T::Boolean) }
  def external?
    true
  end

  sig { params(owner: T.nilable(Resource::Owner)).void }
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
      dir /= T.must(resource.directory) if resource.directory.present?
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
    spec_owner = T.cast(T.must(resource.owner), SoftwareSpec).owner
    f = spec_owner.is_a?(::Formula) ? spec_owner : nil
    cmd, *args = e.cmd
    raise BuildError.new(f, cmd, args, ENV.to_hash)
  end

  sig { returns(String) }
  def inspect
    "#<#{self.class.name}: #{strip.inspect} #{url.inspect}>"
  end
end
