# typed: strict
# frozen_string_literal: true

require "embedded_patch"

# A patch file stored locally within a formula repository.
class LocalPatch < EmbeddedPatch
  sig { returns(T.any(String, Pathname)) }
  attr_reader :file

  sig { returns(T.nilable(Resource::Owner)) }
  attr_reader :owner

  sig { params(path_string: String).returns(T::Boolean) }
  def self.valid_path?(path_string)
    path = Pathname(path_string).cleanpath
    path_string.present? &&
      !path_string.end_with?("/") &&
      !path.absolute? &&
      %w[. ..].exclude?(path.to_s) &&
      !path.to_s.start_with?("../")
  end

  sig { returns(T.nilable(Symbol)) }
  attr_reader :type

  sig {
    params(
      strip: T.any(String, Symbol), file: T.any(String, Pathname),
      resolves: T::Array[String], type: T.nilable(Symbol)
    ).void
  }
  def initialize(strip, file, resolves: [], type: nil)
    super(strip)
    @file = file
    @resolves = T.let(resolves.dup, T::Array[String])
    @type = type
  end

  sig { returns(T::Array[String]) }
  def resolves
    (@resolves + Patch.extract_cves(file.to_s)).uniq
  end

  sig { override.returns(String) }
  def contents
    owner = self.owner
    raise ArgumentError, "LocalPatch#contents called before owner was set!" unless owner

    formula = T.cast(owner, SoftwareSpec).owner
    raise ArgumentError, "LocalPatch#contents requires a formula owner!" unless formula.is_a?(::Formula)

    repository_path = repository_path(formula)
    file_path = repository_path/Pathname(file)
    repository_realpath = repository_path.realpath
    file_realpath = begin
      file_path.realpath
    rescue Errno::ENOENT
      raise ArgumentError, "Patch file does not exist: #{file}"
    end
    if file_realpath.ascend.none?(repository_realpath)
      raise ArgumentError, "Patch file must be within the formula repository."
    end
    raise ArgumentError, "Patch file must be a file: #{file}" unless file_realpath.file?

    file_realpath.read
  end

  sig { override.returns(String) }
  def inspect
    "#<#{self.class.name}: #{strip.inspect} #{file.inspect}>"
  end

  private

  sig { params(formula: ::Formula).returns(Pathname) }
  def repository_path(formula)
    formula_path = formula.specified_path || formula.path
    api_source_repository_path(formula_path) || formula.tap&.path || formula_path.dirname
  end

  sig { params(path: Pathname).returns(T.nilable(Pathname)) }
  def api_source_repository_path(path)
    source_root = if defined?(Homebrew::API::HOMEBREW_CACHE_API_SOURCE)
      Homebrew::API::HOMEBREW_CACHE_API_SOURCE
    else
      HOMEBREW_CACHE/"api-source"
    end.expand_path
    relative_path = path.expand_path.relative_path_from(source_root)
    return if relative_path.to_s.start_with?("../")

    path_parts = relative_path.each_filename.to_a.first(3)
    return if path_parts.length < 3

    source_root/path_parts.fetch(0)/path_parts.fetch(1)/path_parts.fetch(2)
  rescue ArgumentError
    nil
  end
end
