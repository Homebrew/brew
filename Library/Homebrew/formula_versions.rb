# typed: strict
# frozen_string_literal: true

require "formula"
require "utils/output"

# Helper class for traversing a formula's previous versions.
#
# @api internal
class FormulaVersions
  include Context
  include Utils::Output::Mixin

  IGNORED_EXCEPTIONS = [
    ArgumentError, NameError, SyntaxError, TypeError,
    FormulaSpecificationError, FormulaValidationError,
    ErrorDuringExecution, LoadError, MethodDeprecatedError
  ].freeze

  sig { params(formula: Formula).void }
  def initialize(formula)
    @name = T.let(formula.name, String)
    @path = T.let(formula.tap_path, Pathname)
    @repository = T.let(T.must(formula.tap).path, Pathname)
    @relative_path = T.let(@path.relative_path_from(repository).to_s, String)
    # Also look at e.g. older homebrew-core paths before sharding.
    if (match = @relative_path.match(%r{^(HomebrewFormula|Formula)/([a-z]|lib)/(.+)}))
      @old_relative_path = T.let("#{match[1]}/#{match[3]}", T.nilable(String))
    end
    @formula_at_revision = T.let({}, T::Hash[String, Formula])
  end

  sig { params(branch: String, _block: T.proc.params(revision: String, path: String).void).void }
  def rev_list(branch, &_block)
    repository.cd do
      rev_list_cmd = ["git", "rev-list", "--abbrev-commit", "--remove-empty"]
      [relative_path, old_relative_path].compact.each do |entry|
        Utils.popen_read(*rev_list_cmd, branch, "--", entry) do |io|
          yield io.readline.chomp, entry until io.eof?
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
    require "utils/backtrace"

    # We rescue these so that we can skip bad versions and
    # continue walking the history
    odebug "#{e} in #{name} at revision #{revision}", Utils::Backtrace.clean(e)
    nil
  rescue FormulaUnavailableError
    nil
  ensure
    Homebrew.raise_deprecation_exceptions = false
  end

  private

  sig { returns(String) }
  attr_reader :name, :relative_path

  sig { returns(T.nilable(String)) }
  attr_reader :old_relative_path

  sig { returns(Pathname) }
  attr_reader :path, :repository

  sig { params(revision: String, relative_path: String).returns(String) }
  def file_contents_at_revision(revision, relative_path)
    repository.cd { Utils.popen_read("git", "cat-file", "blob", "#{revision}:#{relative_path}") }
  end

  sig {
    type_parameters(:U)
      .params(block: T.proc.returns(T.type_parameter(:U)))
      .returns(T.type_parameter(:U))
  }
  def nostdout(&block)
    if verbose?
      yield
    else
      redirect_stdout(File::NULL, &block)
    end
  end
end
