# typed: true
# frozen_string_literal: true

require "formula"

# Helper class for traversing a formula's previous versions.
#
# @api private
class FormulaVersions
  include Context

  IGNORED_EXCEPTIONS = [
    ArgumentError, NameError, SyntaxError, TypeError,
    FormulaSpecificationError, FormulaValidationError,
    ErrorDuringExecution, LoadError, MethodDeprecatedError
  ].freeze

  sig { params(formula: Formula).void }
  def initialize(formula)
    @name = formula.name
    @path = formula.path
    @repository = T.must(formula.tap).path
    @relative_path = @path.relative_path_from(repository).to_s
    # Also look at e.g. older homebrew-core paths before sharding.
    if (match = @relative_path.match(%r{^(HomebrewFormula|Formula)/([a-z]|lib)/(.+)}))
      @old_relative_path = "#{match[1]}/#{match[3]}"
    end
    @formula_at_revision = {}
  end

  def rev_list(branch)
    repository.cd do
      rev_list_cmd = ["git", "rev-list", "--abbrev-commit", "--remove-empty"]
      [relative_path, old_relative_path].compact.each do |entry|
        Utils.popen_read(*rev_list_cmd, branch, "--", entry) do |io|
          yield [io.readline.chomp, entry] until io.eof?
        end
      end
    end
  end

  sig {
    type_parameters(:U)
      .params(
        revision:              String,
        formula_relative_path: String,
        _block:                T.proc.params(arg0: Formula).returns(T.type_parameter(:U)),
      ).returns(T.nilable(T.type_parameter(:U)))
  }
  def formula_at_revision(revision, formula_relative_path = relative_path, &_block)
    Homebrew.raise_deprecation_exceptions = true

    yield @formula_at_revision[revision] ||= begin
      contents = file_contents_at_revision(revision, formula_relative_path)
      nostdout { Formulary.from_contents(name, path, contents, ignore_errors: true) }
    end
  rescue *IGNORED_EXCEPTIONS => e
    # We rescue these so that we can skip bad versions and
    # continue walking the history
    odebug "#{e} in #{name} at revision #{revision}", Utils::Backtrace.clean(e)
  rescue FormulaUnavailableError
    nil
  ensure
    Homebrew.raise_deprecation_exceptions = false
  end

  private

  attr_reader :name, :path, :repository, :relative_path, :old_relative_path

  sig { params(revision: String, relative_path: String).returns(String) }
  def file_contents_at_revision(revision, relative_path)
    repository.cd { Utils.popen_read("git", "cat-file", "blob", "#{revision}:#{relative_path}") }
  end

  def nostdout(&block)
    if verbose?
      yield
    else
      redirect_stdout(File::NULL, &block)
    end
  end
end
