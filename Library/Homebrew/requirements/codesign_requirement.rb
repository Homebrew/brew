# typed: true
# frozen_string_literal: true

# A requirement on a code-signing identity.
#
# @api private
class CodesignRequirement < Requirement
  fatal true

  def initialize(tags)
    options = tags.shift
    raise ArgumentError, "CodesignRequirement requires an options Hash!" unless options.is_a?(Hash)
    raise ArgumentError, "CodesignRequirement requires an identity key!" unless options.key?(:identity)

    @identity = options.fetch(:identity)
    @with = options.fetch(:with, "code signing")
    @url = options.fetch(:url, nil)
    super(tags)
  end

  satisfy(build_env: false) do
    T.bind(self, CodesignRequirement)
    mktemp do
      FileUtils.cp "/usr/bin/false", "codesign_check"
      quiet_system "/usr/bin/codesign", "-f", "-s", @identity,
                   "--dryrun", "codesign_check"
    end
  end

  sig { returns(String) }
  def message
    message = "#{@identity} identity must be available to build with #{@with}"
    message += ":\n#{@url}" if @url.present?
    message
  end
end
