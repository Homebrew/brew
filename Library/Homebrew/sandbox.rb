# typed: strict
# frozen_string_literal: true

require "erb"
require "io/console"
require "pty"
require "tempfile"
require "utils/fork"
require "utils/output"

# Helper class for running a sub-process inside of a sandboxed environment.
class Sandbox
  include Utils::Output::Mixin

  sig { returns(T::Boolean) }
  def self.available?
    false
  end

  sig { params(file: T.any(String, Pathname)).void }
  def record_log(file)
    @logfile = T.let(file, T.nilable(T.any(String, Pathname)))
  end

  sig { void }
  def allow_cvs
    allow_write_path "#{Dir.home(ENV.fetch("USER"))}/.cvspass"
  end

  sig { void }
  def allow_fossil
    allow_write_path "#{Dir.home(ENV.fetch("USER"))}/.fossil"
    allow_write_path "#{Dir.home(ENV.fetch("USER"))}/.fossil-journal"
  end

  sig { params(formula: Formula).void }
  def allow_write_cellar(formula)
    allow_write_path formula.rack
    allow_write_path formula.etc
    allow_write_path formula.var
  end

  sig { params(formula: Formula).void }
  def allow_write_log(formula)
    allow_write_path formula.logs
  end

  sig { void }
  def deny_write_homebrew_repository
    deny_write path: HOMEBREW_ORIGINAL_BREW_FILE
    if HOMEBREW_PREFIX.to_s == HOMEBREW_REPOSITORY.to_s
      deny_write_path HOMEBREW_LIBRARY
      deny_write_path HOMEBREW_REPOSITORY/".git"
    else
      deny_write_path HOMEBREW_REPOSITORY
    end
  end

  # @api private
  sig { params(path: T.any(String, Pathname), type: Symbol).returns(String) }
  def path_filter(path, type)
    invalid_char = ['"', "'", "(", ")", "\n", "\\"].find do |c|
      path.to_s.include?(c)
    end
    raise ArgumentError, "Invalid character '#{invalid_char}' in path: #{path}" if invalid_char

    case type
    when :regex   then "regex #\"#{path}\""
    when :subpath then "subpath \"#{expand_realpath(Pathname.new(path))}\""
    when :literal then "literal \"#{expand_realpath(Pathname.new(path))}\""
    else raise ArgumentError, "Invalid path filter type: #{type}"
    end
  end

  private

  sig { params(path: Pathname).returns(Pathname) }
  def expand_realpath(path)
    raise unless path.absolute?

    path.exist? ? path.realpath : expand_realpath(path.parent)/path.basename
  end
end

require "extend/os/sandbox"
