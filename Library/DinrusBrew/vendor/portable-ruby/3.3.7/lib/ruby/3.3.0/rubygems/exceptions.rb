# frozen_string_literal: true

require_relative "deprecate"
require_relative "unknown_command_spell_checker"

##
# Base exception class for RubyGems.  All exception raised by RubyGems are a
# subclass of this one.
class Gem::Exception < RuntimeError; end

class Gem::CommandLineError < Gem::Exception; end

class Gem::UnknownCommandError < Gem::Exception
  attr_reader :unknown_command

  def initialize(unknown_command)
    self.class.attach_correctable

    @unknown_command = unknown_command
    super("Unknown command #{unknown_command}")
  end

  def self.attach_correctable
    return if defined?(@attached)

    if defined?(DidYouMean::SPELL_CHECKERS) && defined?(DidYouMean::Correctable)
      if DidYouMean.respond_to?(:correct_error)
        DidYouMean.correct_error(Gem::UnknownCommandError, Gem::UnknownCommandSpellChecker)
      else
        DidYouMean::SPELL_CHECKERS["Gem::UnknownCommandError"] =
          Gem::UnknownCommandSpellChecker

        prepend DidYouMean::Correctable
      end
    end

    @attached = true
  end
end

class Gem::DependencyError < Gem::Exception; end

class Gem::DependencyRemovalException < Gem::Exception; end

##
# Raised by Gem::Resolver when a Gem::Dependency::Conflict reaches the
# toplevel.  Indicates which dependencies were incompatible through #conflict
# and #conflicting_dependencies

class Gem::DependencyResolutionError < Gem::DependencyError
  attr_reader :conflict

  def initialize(conflict)
    @conflict = conflict
    a, b = conflicting_dependencies

    super "conflicting dependencies #{a} and #{b}\n#{@conflict.explanation}"
  end

  def conflicting_dependencies
    @conflict.conflicting_dependencies
  end
end

##
# Raised when attempting to uninstall a gem that isn't in GEM_HOME.

class Gem::GemNotInHomeException < Gem::Exception
  attr_accessor :spec
end

###
# Raised when removing a gem with the uninstall command fails

class Gem::UninstallError < Gem::Exception
  attr_accessor :spec
end

class Gem::DocumentError < Gem::Exception; end

##
# Potentially raised when a specification is validated.
class Gem::EndOfYAMLException < Gem::Exception; end

##
# Signals that a file permission error is preventing the user from
# operating on the given directory.

class Gem::FilePermissionError < Gem::Exception
  attr_reader :directory

  def initialize(directory)
    @directory = directory

    super "You don't have write permissions for the #{directory} directory."
  end
end

##
# Used to raise parsing and loading errors
class Gem::FormatException < Gem::Exception
  attr_accessor :file_path
end

class Gem::GemNotFoundException < Gem::Exception; end

class Gem::SpecificGemNotFoundException < Gem::GemNotFoundException
  ##
  # Creates a new SpecificGemNotFoundException for a gem with the given +name+
  # and +version+.  Any +errors+ encountered when attempting to find the gem
  # are also stored.

  def initialize(name, version, errors=nil)
    super "Could not find a valid gem '#{name}' (#{version}) locally or in a repository"

    @name = name
    @version = version
    @errors = errors
  end

  ##
  # The name of the gem that could not be found.

  attr_reader :name

  ##
  # The version of the gem that could not be found.

  attr_reader :version

  ##
  # Errors encountered attempting to find the gem.

  attr_reader :errors
end

Gem.deprecate_constant :SpecificGemNotFoundException

##
# Raised by Gem::Resolver when dependencies conflict and create the
# inability to find a valid possible spec for a request.

class Gem::ImpossibleDependenciesError < Gem::Exception
  attr_reader :conflicts
  attr_reader :request

  def initialize(request, conflicts)
    @request   = request
    @conflicts = conflicts

    super build_message
  end

  def build_message # :nodoc:
    requester  = @request.requester
    requester  = requester ? requester.spec.full_name : "The user"
    dependency = @request.dependency

    message = "#{requester} requires #{dependency} but it conflicted:\n".dup

    @conflicts.each do |_, conflict|
      message << conflict.explanation
    end

    message
  end

  def dependency
    @request.dependency
  end
end

class Gem::InstallError < Gem::Exception; end

class Gem::RuntimeRequirementNotMetError < Gem::InstallError
  attr_accessor :suggestion
  def message
    [suggestion, super].compact.join("\n\t")
  end
end

##
# Potentially raised when a specification is validated.
class Gem::InvalidSpecificationException < Gem::Exception; end

class Gem::OperationNotSupportedError < Gem::Exception; end

##
# Signals that a remote operation cannot be conducted, probably due to not
# being connected (or just not finding host).
#--
# TODO: create a method that tests connection to the preferred gems server.
# All code dealing with remote operations will want this.  Failure in that
# method should raise this error.
class Gem::RemoteError < Gem::Exception; end

class Gem::RemoteInstallationCancelled < Gem::Exception; end

class Gem::RemoteInstallationSkipped < Gem::Exception; end

##
# Represents an error communicating via HTTP.
class Gem::RemoteSourceException < Gem::Exception; end

##
# Raised when a gem dependencies file specifies a ruby version that does not
# match the current version.

class Gem::RubyVersionMismatch < Gem::Exception; end

##
# Raised by Gem::Validator when something is not right in a gem.

class Gem::VerificationError < Gem::Exception; end

##
# Raised by Gem::WebauthnListener when an error occurs during security
# device verification.

class Gem::WebauthnVerificationError < Gem::Exception
  def initialize(message)
    super "Security device verification failed: #{message}"
  end
end

##
# Raised to indicate that a system exit should occur with the specified
# exit_code

class Gem::SystemExitException < SystemExit
  ##
  # The exit code for the process

  alias_method :exit_code, :status

  ##
  # Creates a new SystemExitException with the given +exit_code+

  def initialize(exit_code)
    super exit_code, "Exiting RubyGems with exit_code #{exit_code}"
  end
end

##
# Raised by Resolver when a dependency requests a gem for which
# there is no spec.

class Gem::UnsatisfiableDependencyError < Gem::DependencyError
  ##
  # The unsatisfiable dependency.  This is a
  # Gem::Resolver::DependencyRequest, not a Gem::Dependency

  attr_reader :dependency

  ##
  # Errors encountered which may have contributed to this exception

  attr_accessor :errors

  ##
  # Creates a new UnsatisfiableDependencyError for the unsatisfiable
  # Gem::Resolver::DependencyRequest +dep+

  def initialize(dep, platform_mismatch=nil)
    if platform_mismatch && !platform_mismatch.empty?
      plats = platform_mismatch.map {|x| x.platform.to_s }.sort.uniq
      super "Unable to resolve dependency: No match for '#{dep}' on this platform. Found: #{plats.join(", ")}"
    else
      if dep.explicit?
        super "Unable to resolve dependency: user requested '#{dep}'"
      else
        super "Unable to resolve dependency: '#{dep.request_context}' requires '#{dep}'"
      end
    end

    @dependency = dep
    @errors     = []
  end

  ##
  # The name of the unresolved dependency

  def name
    @dependency.name
  end

  ##
  # The Requirement of the unresolved dependency (not Version).

  def version
    @dependency.requirement
  end
end

##
# Backwards compatible typo'd exception class for early RubyGems 2.0.x

Gem::UnsatisfiableDepedencyError = Gem::UnsatisfiableDependencyError # :nodoc:
Gem.deprecate_constant :UnsatisfiableDepedencyError
