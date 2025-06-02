# frozen_string_literal: true

module Bundler
  class BundlerError < StandardError
    def self.status_code(code)
      define_method(:status_code) { code }
      if match = BundlerError.all_errors.find {|_k, v| v == code }
        error, _ = match
        raise ArgumentError,
          "Trying to register #{self} for status code #{code} but #{error} is already registered"
      end
      BundlerError.all_errors[self] = code
    end

    def self.all_errors
      @all_errors ||= {}
    end
  end

  class GemfileError < BundlerError; status_code(4); end
  class InstallError < BundlerError; status_code(5); end

  # Internal error, should be rescued
  class SolveFailure < BundlerError; status_code(6); end

  class GemNotFound < BundlerError; status_code(7); end
  class InstallHookError < BundlerError; status_code(8); end
  class GemfileNotFound < BundlerError; status_code(10); end
  class GitError < BundlerError; status_code(11); end
  class DeprecatedError < BundlerError; status_code(12); end
  class PathError < BundlerError; status_code(13); end
  class GemspecError < BundlerError; status_code(14); end
  class InvalidOption < BundlerError; status_code(15); end
  class ProductionError < BundlerError; status_code(16); end

  class HTTPError < BundlerError
    status_code(17)
    def filter_uri(uri)
      URICredentialsFilter.credential_filtered_uri(uri)
    end
  end

  class RubyVersionMismatch < BundlerError; status_code(18); end
  class SecurityError < BundlerError; status_code(19); end
  class LockfileError < BundlerError; status_code(20); end
  class CyclicDependencyError < BundlerError; status_code(21); end
  class GemfileLockNotFound < BundlerError; status_code(22); end
  class PluginError < BundlerError; status_code(29); end
  class ThreadCreationError < BundlerError; status_code(33); end
  class APIResponseMismatchError < BundlerError; status_code(34); end
  class APIResponseInvalidDependenciesError < BundlerError; status_code(35); end
  class GemfileEvalError < GemfileError; end
  class MarshalError < StandardError; end

  class ChecksumMismatchError < SecurityError
    def initialize(lock_name, existing, checksum)
      @lock_name = lock_name
      @existing = existing
      @checksum = checksum
    end

    def message
      <<~MESSAGE
        Bundler found mismatched checksums. This is a potential security risk.
          #{@lock_name} #{@existing.to_lock}
            from #{@existing.sources.join("\n    and ")}
          #{@lock_name} #{@checksum.to_lock}
            from #{@checksum.sources.join("\n    and ")}

        #{mismatch_resolution_instructions}
        To ignore checksum security warnings, disable checksum validation with
          `bundle config set --local disable_checksum_validation true`
      MESSAGE
    end

    def mismatch_resolution_instructions
      removable, remote = [@existing, @checksum].partition(&:removable?)
      case removable.size
      when 0
        msg = +"Mismatched checksums each have an authoritative source:\n"
        msg << "  1. #{@existing.sources.reject(&:removable?).map(&:to_s).join(" and ")}\n"
        msg << "  2. #{@checksum.sources.reject(&:removable?).map(&:to_s).join(" and ")}\n"
        msg << "You may need to alter your Gemfile sources to resolve this issue.\n"
      when 1
        msg = +"If you trust #{remote.first.sources.first}, to resolve this issue you can:\n"
        msg << removable.first.removal_instructions
      when 2
        msg = +"To resolve this issue you can either:\n"
        msg << @checksum.removal_instructions
        msg << "or if you are sure that the new checksum from #{@checksum.sources.first} is correct:\n"
        msg << @existing.removal_instructions
      end
    end

    status_code(37)
  end

  class PermissionError < BundlerError
    def initialize(path, permission_type = :write)
      @path = path
      @permission_type = permission_type
    end

    def action
      case @permission_type
      when :read then "read from"
      when :write then "write to"
      when :executable, :exec then "execute"
      else @permission_type.to_s
      end
    end

    def permission_type
      case @permission_type
      when :create
        "executable permissions for all parent directories and write permissions for `#{parent_folder}`"
      else
        "#{@permission_type} permissions for that path"
      end
    end

    def parent_folder
      File.dirname(@path)
    end

    def message
      "There was an error while trying to #{action} `#{@path}`. " \
      "It is likely that you need to grant #{permission_type}."
    end

    status_code(23)
  end

  class GemRequireError < BundlerError
    attr_reader :orig_exception

    def initialize(orig_exception, msg)
      full_message = msg + "\nGem Load Error is: #{orig_exception.message}\n"\
                      "Backtrace for gem load error is:\n"\
                      "#{orig_exception.backtrace.join("\n")}\n"\
                      "Bundler Error Backtrace:\n"
      super(full_message)
      @orig_exception = orig_exception
    end

    status_code(24)
  end

  class YamlSyntaxError < BundlerError
    attr_reader :orig_exception

    def initialize(orig_exception, msg)
      super(msg)
      @orig_exception = orig_exception
    end

    status_code(25)
  end

  class TemporaryResourceError < PermissionError
    def message
      "There was an error while trying to #{action} `#{@path}`. " \
      "Some resource was temporarily unavailable. It's suggested that you try" \
      "the operation again."
    end

    status_code(26)
  end

  class VirtualProtocolError < BundlerError
    def message
      "There was an error relating to virtualization and file access. " \
      "It is likely that you need to grant access to or mount some file system correctly."
    end

    status_code(27)
  end

  class OperationNotSupportedError < PermissionError
    def message
      "Attempting to #{action} `#{@path}` is unsupported by your OS."
    end

    status_code(28)
  end

  class NoSpaceOnDeviceError < PermissionError
    def message
      "There was an error while trying to #{action} `#{@path}`. " \
      "There was insufficient space remaining on the device."
    end

    status_code(31)
  end

  class GenericSystemCallError < BundlerError
    attr_reader :underlying_error

    def initialize(underlying_error, message)
      @underlying_error = underlying_error
      super("#{message}\nThe underlying system error is #{@underlying_error.class}: #{@underlying_error}")
    end

    status_code(32)
  end

  class DirectoryRemovalError < BundlerError
    def initialize(orig_exception, msg)
      full_message = "#{msg}.\n" \
                     "The underlying error was #{orig_exception.class}: #{orig_exception.message}, with backtrace:\n" \
                     "  #{orig_exception.backtrace.join("\n  ")}\n\n" \
                     "Bundler Error Backtrace:"
      super(full_message)
    end

    status_code(36)
  end

  class InsecureInstallPathError < BundlerError
    def initialize(name, path)
      @name = name
      @path = path
    end

    def message
      "Bundler cannot reinstall #{@name} because there's a previous installation of it at #{@path} that is unsafe to remove.\n" \
      "The parent of #{@path} is world-writable and does not have the sticky bit set, making it insecure to remove due to potential vulnerabilities.\n" \
      "Please change the permissions of #{File.dirname(@path)} or choose a different install path."
    end

    status_code(38)
  end

  class CorruptBundlerInstallError < BundlerError
    def initialize(loaded_spec)
      @loaded_spec = loaded_spec
    end

    def message
      "The running version of Bundler (#{Bundler::VERSION}) does not match the version of the specification installed for it (#{@loaded_spec.version}). " \
      "This can be caused by reinstalling Ruby without removing previous installation, leaving around an upgraded default version of Bundler. " \
      "Reinstalling Ruby from scratch should fix the problem."
    end

    status_code(39)
  end

  class InvalidArgumentError < BundlerError; status_code(40); end
end
