# typed: strict
# frozen_string_literal: true

require "api"
# A patch file stored locally with a formula or tap.
class LocalPatch < EmbeddedPatch
  sig { returns(T.any(String, Pathname)) }
  attr_reader :file

  sig { params(strip: T.any(String, Symbol), file: T.any(String, Pathname)).void }
  def initialize(strip, file)
    super(strip)
    @file = file
  end

  sig { override.returns(String) }
  def contents
    owner = self.owner
    raise ArgumentError, "LocalPatch#contents called before owner was set!" unless owner

    formula = T.cast(owner, SoftwareSpec).owner
    raise ArgumentError, "LocalPatch#contents requires a formula owner!" unless formula.is_a?(::Formula)

    repository_path = Homebrew::API.source_download_tap_path(formula.path) ||
                      formula.tap&.path ||
                      formula.path.dirname
    file_path = repository_path/Pathname(file)
    repository_realpath = repository_path.realpath
    file_realpath = begin
      file_path.realpath
    rescue Errno::ENOENT
      raise ArgumentError, "Patch file does not exist: #{file}"
    end
    unless file_realpath.to_s.start_with?("#{repository_realpath}/")
      raise ArgumentError, "Patch file must be within the formula repository."
    end

    file_realpath.read
  end

  sig { override.returns(String) }
  def inspect
    "#<#{self.class.name}: #{strip.inspect} #{file.inspect}>"
  end
end
