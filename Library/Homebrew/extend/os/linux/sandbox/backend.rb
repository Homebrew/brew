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
      allowed_paths("file-write").each { |path, type| prepare_writable_path(path, type) }
    end

    private

    sig { params(operation: String, paths: T::Hash[String, Symbol]).returns(T::Hash[String, Symbol]) }
    def allowed_paths(operation, paths = {})
      profile.rules.each do |rule|
        next unless rule.operation.start_with?(operation)
        next unless (filter = rule.filter)

        case filter.type
        when :literal, :subpath
          if rule.allow
            next if operation != "file-write" && !File.exist?(filter.path)

            paths[filter.path] ||= filter.type
          else
            paths = paths.flat_map do |path, type|
              paths_excluding(::Pathname.new(path), ::Pathname.new(filter.path)).map { |allowed| [allowed, type] }
            end.to_h
          end
        when :regex
          raise ArgumentError, "Linux sandbox does not support regex path filters: #{filter.path}"
        else
          raise ArgumentError, "Invalid path filter type: #{filter.type}"
        end
      end
      paths
    end

    # Landlock grants are additive, so exclude denied paths by splitting ancestor grants.
    sig { params(path: ::Pathname, denied_path: ::Pathname).returns(T::Array[String]) }
    def paths_excluding(path, denied_path)
      return [] if path.ascend.include?(denied_path) || path.symlink?
      return [path.to_s] unless denied_path.ascend.include?(path)

      path.children.sort.flat_map { |child| paths_excluding(child, denied_path) }
    rescue Errno::EACCES, Errno::ENOENT
      []
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
