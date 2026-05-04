# typed: strict
# frozen_string_literal: true

# An abstract class representing a patch embedded into a formula.
class EmbeddedPatch
  include Utils::Output::Mixin
  extend T::Helpers

  abstract!

  sig { returns(T.nilable(Resource::Owner)) }
  attr_accessor :owner

  sig { returns(T.any(String, Symbol)) }
  attr_reader :strip

  sig { params(strip: T.any(String, Symbol)).void }
  def initialize(strip)
    @strip = strip
    @owner = T.let(nil, T.nilable(Resource::Owner))
  end

  sig { returns(T::Boolean) }
  def external?
    false
  end

  sig { abstract.returns(String) }
  def contents; end

  sig { void }
  def apply
    data = contents.gsub("@@HOMEBREW_PREFIX@@", HOMEBREW_PREFIX)
    if data.gsub!("HOMEBREW_PREFIX", HOMEBREW_PREFIX)
      odisabled "patch with HOMEBREW_PREFIX placeholder",
                "patch with @@HOMEBREW_PREFIX@@ placeholder"
    end
    args = %W[-g 0 -f -#{strip}]
    Utils.safe_popen_write("patch", *args) { |p| p.write(data) }
  end

  sig { returns(String) }
  def inspect
    "#<#{self.class.name}: #{strip.inspect}>"
  end
end
