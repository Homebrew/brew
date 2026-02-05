# typed: strict
# frozen_string_literal: true

# A requirement on a code-signing identity.
class CodesignRequirement < Requirement
  fatal true

  sig { returns(String) }
  attr_reader :identity

  sig { params(tags: T::Array[T.untyped]).void }
  def initialize(tags)
    options = tags.shift
    raise ArgumentError, "CodesignRequirement requires an options Hash!" unless options.is_a?(Hash)
    raise ArgumentError, "CodesignRequirement requires an identity key!" unless options.key?(:identity)

    @identity = T.let(options.fetch(:identity), String)
    @with = T.let(options.fetch(:with, "code signing"), String)
    @url = T.let(options.fetch(:url, nil), T.nilable(String))
    super
  end

  satisfy(build_env: false) do
    T.bind(self, CodesignRequirement)
    odeprecated "CodesignRequirement"
    mktemp do
      FileUtils.cp "/usr/bin/false", "codesign_check"
      quiet_system "/usr/bin/codesign", "-f", "-s", identity,
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
