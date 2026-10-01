# typed: strict
# frozen_string_literal: true

require "embedded_patch"

# A patch at the `__END__` of a formula file.
class DATAPatch < EmbeddedPatch
  sig { returns(T.nilable(Pathname)) }
  attr_accessor :path

  sig { params(strip: T.any(String, Symbol)).void }
  def initialize(strip)
    super
    @path = T.let(nil, T.nilable(Pathname))
  end

  sig { override.returns(String) }
  def filename = "embedded DATA patch"

  sig { override.returns(String) }
  def contents
    path = self.path
    raise ArgumentError, "DATAPatch#contents called before path was set!" unless path

    data = +""
    path.open("rb") do |f|
      loop do
        line = f.gets
        break if line.nil? || /^__END__$/.match?(line)
      end
      while (line = f.gets)
        data << line
      end
    end
    data.freeze
  end
end
