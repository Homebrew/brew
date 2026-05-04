# typed: strict
# frozen_string_literal: true

# A string containing a patch.
class StringPatch < EmbeddedPatch
  sig { params(strip: T.any(String, Symbol), str: String).void }
  def initialize(strip, str)
    super(strip)
    @str = str
  end

  sig { override.returns(String) }
  def contents
    @str
  end
end
