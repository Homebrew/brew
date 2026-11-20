# typed: strict
# frozen_string_literal: true

# A requirement on Linux.
class LinuxRequirement < Requirement
  Cache = type_template { { fixed: T::Hash[String, T.untyped] } }

  fatal true

  satisfy(build_env: false) { OS.linux? }

  sig { override.params(bottle_tag: Utils::Bottles::Tag).returns(T::Boolean) }
  def platform_supported?(bottle_tag) = bottle_tag.linux?

  sig { returns(String) }
  def display_s
    "Linux"
  end

  sig { returns(String) }
  def message
    "Linux is required for this software."
  end
end
