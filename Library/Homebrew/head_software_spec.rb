# typed: strict
# frozen_string_literal: true

require "software_spec"

class HeadSoftwareSpec < SoftwareSpec
  sig { params(flags: T::Array[String]).void }
  def initialize(flags: [])
    super
    @resource.version(Version.new("HEAD"))
  end

  sig { params(_filename: Pathname).returns(NilClass) }
  def verify_download_integrity(_filename)
    # no-op
  end
end
