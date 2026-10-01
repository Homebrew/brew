# typed: strict
# frozen_string_literal: true

require "erb"
require "forwardable"
require "resource"
require "utils/output"

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
    @strip    = strip
    @resource = T.let(Resource::Patch.new(&block), Resource::Patch)
  end

  sig { returns(T::Boolean) }
  def external?
    true
  end

  sig { returns(T::Array[String]) }
  def resolves
    (resource.resolves + Patch.extract_cves(url.to_s, *resource.patch_files.map(&:to_s))).uniq
  end

  sig { returns(T.nilable(Symbol)) }
  def type
    resource.type
  end

  sig { params(owner: T.nilable(Resource::Owner)).void }
  def owner=(owner)
    resource.owner = owner
    resource.version(resource.checksum&.hexdigest || ERB::Util.url_encode(resource.url))
  end

  sig { void }
  def apply
    begin
      if downloaded?
        verify_download_integrity(cached_download) if resource.checksum.present?
      else
        fetch
      end
    rescue ChecksumMismatchError
      clear_cache
      raise
    end

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
      resource_directory = resource.directory.presence
      dir = resource_directory ? base_dir/resource_directory : base_dir
      Utils::Path.ensure_child_of!(base_dir, dir, message: "Patch directory escapes the staged source tree: #{dir}")
      patch_files.each do |patch_file|
        ohai "Applying #{patch_file}"
        Patch.apply(
          (patch_dir/patch_file).read.gsub("@@HOMEBREW_PREFIX@@", HOMEBREW_PREFIX), strip:, base: dir
        )
      end
    end
  rescue ErrorDuringExecution => e
    onoe e
    resource_owner = resource.owner
    spec_owner = resource_owner.owner if resource_owner.is_a?(SoftwareSpec)
    formula = spec_owner if spec_owner.is_a?(::Formula)
    cmd, *args = e.cmd
    raise BuildError.new(formula, cmd, args, ENV.to_hash)
  end

  sig { returns(String) }
  def inspect
    "#<#{self.class.name}: #{strip.inspect} #{url.inspect}>"
  end
end
