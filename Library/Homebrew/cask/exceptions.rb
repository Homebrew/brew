# typed: strict
# frozen_string_literal: true

module Cask
  # General cask error.
  class CaskError < RuntimeError; end

  # Cask error containing multiple other errors.
  class MultipleCaskErrors < CaskError
    sig { params(errors: T::Array[StandardError]).void }
    def initialize(errors)
      super()

      @errors = errors
    end

    sig { returns(String) }
    def to_s
      <<~EOS
        Problems with multiple casks:
        #{@errors.join("\n")}
      EOS
    end
  end

  # Abstract cask error containing a cask token.
  class AbstractCaskErrorWithToken < CaskError
    sig { returns(String) }
    attr_reader :token

    sig { returns(String) }
    attr_reader :reason

    sig { params(token: T.any(String, Symbol, Cask), reason: T.nilable(Object)).void }
    def initialize(token, reason = nil)
      super()

      @token = T.let(token.to_s, String)
      @reason = T.let(reason.to_s, String)
    end
  end

  # Error when a cask is not installed.
  class CaskNotInstalledError < AbstractCaskErrorWithToken
    sig { returns(String) }
    def to_s
      "Cask '#{token}' is not installed."
    end
  end

  # Error when a cask cannot be installed.
  class CaskCannotBeInstalledError < AbstractCaskErrorWithToken
    sig { returns(String) }
    attr_reader :message

    sig { params(token: T.any(String, Symbol, Cask), message: String).void }
    def initialize(token, message)
      super(token)
      @message = message
    end

    sig { returns(String) }
    def to_s
      "Cask '#{token}' has been #{message}"
    end
  end

  # Error when a cask conflicts with another cask.
  class CaskConflictError < AbstractCaskErrorWithToken
    sig { returns(Cask) }
    attr_reader :conflicting_cask

    sig { params(token: T.any(String, Symbol, Cask), conflicting_cask: Cask).void }
    def initialize(token, conflicting_cask)
      super(token)
      @conflicting_cask = conflicting_cask
    end

    sig { returns(String) }
    def to_s
      "Cask '#{token}' conflicts with '#{conflicting_cask}'."
    end
  end

  # Error when a cask is not available.
  class CaskUnavailableError < AbstractCaskErrorWithToken
    sig { returns(String) }
    def to_s
      "Cask '#{token}' is unavailable#{reason.empty? ? "." : ": #{reason}"}"
    end
  end

  # Error when a cask is unreadable.
  class CaskUnreadableError < CaskUnavailableError
    sig { returns(String) }
    def to_s
      "Cask '#{token}' is unreadable#{reason.empty? ? "." : ": #{reason}"}"
    end
  end

  # Error when a cask in a specific tap is not available.
  class TapCaskUnavailableError < CaskUnavailableError
    sig { returns(Tap) }
    attr_reader :tap

    sig { params(tap: Tap, token: String).void }
    def initialize(tap, token)
      super("#{tap}/#{token}")
      @tap = tap
    end

    sig { returns(String) }
    def to_s
      s = super
      unless tap.installed?
        s += "\nThis command requires the tap #{tap}."
        s += "\nIf you trust this tap, tap it explicitly and then try again:\n  brew tap #{tap}"
      end
      s
    end
  end

  # Error when a cask with the same name is found in multiple taps.
  class TapCaskAmbiguityError < CaskError
    sig { returns(String) }
    attr_reader :token

    sig { returns(T::Array[CaskLoader::FromNameLoader]) }
    attr_reader :loaders

    sig { params(token: String, loaders: T::Array[CaskLoader::FromNameLoader]).void }
    def initialize(token, loaders)
      @token = token
      @loaders = loaders

      taps = loaders.map(&:tap)
      casks = taps.map { |tap| "#{tap}/#{token}" }
      cask_list = casks.sort.map { |f| "\n       * #{f}" }.join

      super <<~EOS
        Cask #{token} exists in multiple taps:#{cask_list}

        Please use the fully-qualified name (e.g. #{casks.first}) to refer to a specific Cask.
      EOS
    end
  end

  # Error when a cask already exists.
  class CaskAlreadyCreatedError < AbstractCaskErrorWithToken
    sig { returns(String) }
    def to_s
      %Q(Cask '#{token}' already exists. Run #{Formatter.identifier("brew edit --cask #{token}")} to edit it.)
    end
  end

  # Error when there is a cyclic cask dependency.
  class CaskCyclicDependencyError < AbstractCaskErrorWithToken
    sig { returns(String) }
    def to_s
      "Cask '#{token}' includes cyclic dependencies on other Casks#{reason.empty? ? "." : ": #{reason}"}"
    end
  end

  # Error when a cask depends on itself.
  class CaskSelfReferencingDependencyError < CaskCyclicDependencyError
    sig { returns(String) }
    def to_s
      "Cask '#{token}' depends on itself."
    end
  end

  # Error when no cask is specified.
  class CaskUnspecifiedError < CaskError
    sig { returns(String) }
    def to_s
      "This command requires a Cask token."
    end
  end

  # Error when a cask is invalid.
  class CaskInvalidError < AbstractCaskErrorWithToken
    sig { returns(String) }
    def to_s
      "Cask '#{token}' definition is invalid#{reason.empty? ? "." : ": #{reason}"}"
    end
  end

  # Error when a cask token does not match the file name.
  class CaskTokenMismatchError < CaskInvalidError
    sig { params(token: T.any(String, Symbol, Cask), header_token: String).void }
    def initialize(token, header_token)
      super(token, "Token '#{header_token}' in header line does not match the file name.")
    end
  end

  # Error during quarantining of a file.
  class CaskQuarantineError < CaskError
    sig { returns(T.any(String, Pathname)) }
    attr_reader :path

    sig { returns(String) }
    attr_reader :reason

    sig { params(path: T.any(String, Pathname), reason: String).void }
    def initialize(path, reason)
      super()

      @path = path
      @reason = reason
    end

    sig { returns(String) }
    def to_s
      s = "Failed to quarantine #{path}."

      unless reason.empty?
        s << " Here's the reason:\n"
        s << Formatter.error(reason)
        s << "\n" unless reason.end_with?("\n")
      end

      s.freeze
    end
  end

  # Error while propagating quarantine information to subdirectories.
  class CaskQuarantinePropagationError < CaskQuarantineError
    sig { returns(String) }
    def to_s
      s = "Failed to quarantine one or more files within #{path}."

      unless reason.empty?
        s << " Here's the reason:\n"
        s << Formatter.error(reason)
        s << "\n" unless reason.end_with?("\n")
      end

      s.freeze
    end
  end

  # Error while removing quarantine information.
  class CaskQuarantineReleaseError < CaskQuarantineError
    sig { returns(String) }
    def to_s
      s = "Failed to release #{path} from quarantine."

      unless reason.empty?
        s << " Here's the reason:\n"
        s << Formatter.error(reason)
        s << "\n" unless reason.end_with?("\n")
      end

      s.freeze
    end
  end
end
