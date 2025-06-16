# typed: strict
# frozen_string_literal: true

# Formula information drawn from an external `brew info --json` call.
class FormulaInfo
  # The whole info structure parsed from the JSON.
  sig { returns(T::Hash[String, T.untyped]) }
  attr_accessor :info

  sig { params(info: T::Hash[String, T.untyped]).void }
  def initialize(info)
    @info = T.let(info, T::Hash[String, T.untyped])
  end

  # Looks up formula on disk and reads its info.
  # Returns nil if formula is absent or if there was an error reading it.
  sig { params(name: Pathname).returns(T.nilable(FormulaInfo)) }
  def self.lookup(name)
    json = Utils.popen_read(
      *HOMEBREW_RUBY_EXEC_ARGS,
      HOMEBREW_LIBRARY_PATH/"brew.rb",
      "info",
      "--json=v1",
      name,
    )

    return unless $CHILD_STATUS.success?

    force_utf8!(json)
    FormulaInfo.new(JSON.parse(json)[0])
  end

  sig { returns(T::Array[String]) }
  def bottle_tags
    return [] unless info["bottle"]["stable"]

    info["bottle"]["stable"]["files"].keys
  end

  sig {
    params(my_bottle_tag: T.any(Utils::Bottles::Tag, T.nilable(String))).returns(T.nilable(T::Hash[String, String]))
  }
  def bottle_info(my_bottle_tag = Utils::Bottles.tag)
    tag_s = my_bottle_tag.to_s
    return unless info["bottle"]["stable"]

    btl_info = info["bottle"]["stable"]["files"][tag_s]
    return unless btl_info

    { "url" => btl_info["url"], "sha256" => btl_info["sha256"] }
  end

  sig { returns(T.nilable(T::Hash[String, String])) }
  def bottle_info_any
    bottle_info(any_bottle_tag)
  end

  sig { returns(T.nilable(String)) }
  def any_bottle_tag
    tag = Utils::Bottles.tag.to_s
    # Prefer native bottles as a convenience for download caching
    bottle_tags.include?(tag) ? tag : bottle_tags.first
  end

  sig { params(spec_type: Symbol).returns(Version) }
  def version(spec_type)
    version_str = info["versions"][spec_type.to_s]
    Version.new(version_str)
  end

  sig { params(spec_type: Symbol).returns(PkgVersion) }
  def pkg_version(spec_type = :stable)
    PkgVersion.new(version(spec_type), revision)
  end

  sig { returns(Integer) }
  def revision
    info["revision"]
  end

  sig { params(str: String).void }
  def self.force_utf8!(str)
    str.force_encoding("UTF-8") if str.respond_to?(:force_encoding)
  end
end
