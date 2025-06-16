# typed: strict
# frozen_string_literal: true

# A requirement on Linux.
class LinuxRequirement < Requirement
  fatal true

  satisfy(build_env: false) { OS.linux? }

  sig { returns(String) }
  def message
    "Linux is required for this software."
  end
end
