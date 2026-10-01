# typed: strict
# frozen_string_literal: true

require "fileutils"

class Sandbox
  class LinuxBackend
    class << self
      sig { returns(T::Boolean) }
      def full_write_isolation? = true
    end

    sig { params(profile: SandboxProfile).void }
    def initialize(profile)
      @profile = profile
      @prepared_writable_paths = T.let([], T::Array[::Pathname])
    end

    sig { void }
    def cleanup
      @prepared_writable_paths.reverse_each do |path|
        path.rmdir if path.directory?
      rescue Errno::ENOENT, Errno::ENOTEMPTY
        nil
      end
      @prepared_writable_paths.clear
    end

    private

    sig { returns(SandboxProfile) }
    attr_reader :profile

    public

    sig { returns(T::Hash[String, Symbol]) }
    def writable_paths
      profile.rules.each_with_object({}) do |rule, paths|
        next if !rule.allow || !rule.operation.start_with?("file-write")
        next unless (filter = rule.filter)

        case filter.type
        when :literal, :subpath
          paths[filter.path] ||= filter.type
        when :regex
          raise ArgumentError, "Linux sandbox does not support regex path filters: #{filter.path}"
        else
          raise ArgumentError, "Invalid path filter type: #{filter.type}"
        end
      end
    end

    private

    sig { params(allow: T::Boolean, operation: String).returns(T::Array[String]) }
    def profile_paths(allow:, operation:)
      profile.rules.filter_map do |rule|
        next if rule.allow != allow || !rule.operation.start_with?(operation)

        filter = rule.filter
        filter.path if filter && [:literal, :subpath].include?(filter.type)
      end.uniq
    end

    sig { returns(T::Boolean) }
    def deny_all_network?
      profile.rules.any? do |rule|
        !rule.allow && rule.operation == "network*" && rule.filter.nil?
      end
    end

    sig { params(path: String, type: Symbol).void }
    def prepare_writable_path(path, type)
      pathname = ::Pathname.new(path)
      return if pathname.exist?

      if type == :literal
        FileUtils.mkdir_p(pathname.dirname)
        FileUtils.touch(pathname)
      else
        FileUtils.mkdir_p(pathname)
        @prepared_writable_paths << pathname
      end
    end
  end
end
