# typed: strict
# frozen_string_literal: true

require "resource"
require "utils/output"

# An abstract class representing a patch embedded into a formula.
class EmbeddedPatch
  include Utils::Output::Mixin
  extend T::Helpers

  abstract!

  sig { params(owner: T.nilable(Resource::Owner)).returns(T.nilable(Resource::Owner)) }
  attr_writer :owner

  sig { returns(T.any(String, Symbol)) }
  attr_reader :strip

  sig { returns(T.nilable(T.any(String, Pathname))) }
  attr_accessor :directory

  sig { params(strip: T.any(String, Symbol)).void }
  def initialize(strip)
    @strip = strip
    @owner = T.let(nil, T.nilable(Resource::Owner))
    @directory = T.let(nil, T.nilable(T.any(String, Pathname)))
  end

  sig { returns(T::Boolean) }
  def external?
    false
  end

  sig { abstract.returns(String) }
  def filename; end

  sig { abstract.returns(String) }
  def contents; end

  sig { void }
  def apply
    data = contents.gsub("@@HOMEBREW_PREFIX@@", HOMEBREW_PREFIX)
    dir = Pathname.pwd
    if (subdirectory = directory.presence)
      dir /= subdirectory
    end
    Utils::Path.ensure_child_of!(Pathname.pwd, dir,
                                 message: "Patch directory escapes the staged source tree: #{dir}")
    ohai "Applying #{filename}"
    Patch.apply(data, strip:, base: dir)
  end

  sig { returns(String) }
  def inspect
    "#<#{self.class.name}: #{strip.inspect}>"
  end
end
