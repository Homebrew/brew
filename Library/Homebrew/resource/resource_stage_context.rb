# typed: strict
# frozen_string_literal: true

# The context in which a {Resource#stage} occurs. Supports access to both
# the {Resource} and associated {Mktemp} in a single block argument. The interface
# is back-compatible with {Resource} itself as used in that context.
class ResourceStageContext
  extend Forwardable

  # The {Resource} that is being staged.
  sig { returns(Resource) }
  attr_reader :resource

  # The {Mktemp} in which {#resource} is staged.
  sig { returns(Mktemp) }
  attr_reader :staging

  def_delegators :@resource, :version, :url, :mirrors, :specs, :using, :source_modified_time
  def_delegators :@staging, :retain!

  sig { params(resource: Resource, staging: Mktemp).void }
  def initialize(resource, staging)
    @resource = resource
    @staging = staging
  end

  sig { returns(String) }
  def to_s
    "<#{self.class}: resource=#{resource} staging=#{staging}>"
  end
end
