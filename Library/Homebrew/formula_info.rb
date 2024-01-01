# typed: true
# frozen_string_literal: true

# Formula information drawn from an external `brew info --json` call.
#
# @api private
class FormulaInfo
  # The whole info structure parsed from the JSON.
  attr_accessor :info

  def initialize(info)
    @info = info
  end

  # Looks up formula on disk and reads its info.
  # Returns nil if formula is absent or if there was an error reading it.
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

  def bottle_tags
    return [] unless info["bottle"]["stable"]

    info["bottle"]["stable"]["files"].keys
  end

  def bottle_info(my_bottle_tag = Utils::Bottles.tag)
    tag_s = my_bottle_tag.to_s
    return unless info["bottle"]["stable"]

    btl_info = info["bottle"]["stable"]["files"][tag_s]
    return unless btl_info

    { "url" => btl_info["url"], "sha256" => btl_info["sha256"] }
  end

  def bottle_info_any
    bottle_info(any_bottle_tag)
  end

  def any_bottle_tag
    tag = Utils::Bottles.tag.to_s
    # Prefer native bottles as a convenience for download caching
    bottle_tags.include?(tag) ? tag : bottle_tags.first
  end

  def version(spec_type)
    version_str = info["versions"][spec_type.to_s]
    version_str && Version.new(version_str)
  end

  def pkg_version(spec_type = :stable)
    PkgVersion.new(version(spec_type), revision)
  end

  def revision
    info["revision"]
  end

  def self.force_utf8!(str)
    str.force_encoding("UTF-8") if str.respond_to?(:force_encoding)
  end
end
