# typed: strict
# frozen_string_literal: true

require "json"
require "tempfile"
require "bundle/package_types"

module Homebrew
  module Bundle
    module Locker
      SCHEMA_VERSION = 1
      LOCKFILE_NAME = "Brewfile.lock.json"

      sig { params(file: T.any(Pathname, String)).returns(Pathname) }
      def self.lock_path(file)
        Pathname(file).dirname/LOCKFILE_NAME
      end

      sig { params(entries: T::Array[T.untyped], file: T.any(Pathname, String)).returns(Pathname) }
      def self.lock(entries:, file:)
        path = lock_path(file)
        path.dirname.mkpath

        Tempfile.create([path.basename.to_s, ".tmp"], path.dirname.to_s) do |tempfile|
          tempfile.write("#{JSON.pretty_generate(deep_sort(lock_hash(entries)))}\n")
          tempfile.close
          File.rename(tempfile.path, path)
        end

        path
      end

      sig { params(file: T.any(Pathname, String)).returns(T.nilable(T::Hash[String, T.untyped])) }
      def self.read(file:)
        path = lock_path(file)
        return unless path.file?

        JSON.parse(path.read)
      rescue JSON::ParserError
        nil
      end

      sig { params(entries: T::Array[T.untyped]).returns(T::Hash[String, T.untyped]) }
      private_class_method def self.lock_hash(entries)
        lock_entries = T.let({
          "brew" => {},
          "cask" => {},
          "tap"  => {},
        }, T::Hash[String, T::Hash[String, Homebrew::Bundle::LockEntry]])

        entries.each do |entry|
          package_type = Homebrew::Bundle.installable(entry.type)
          next if package_type.nil?

          begin
            lock_entry = package_type.lock_entry(entry.name, entry.options)
          rescue => e
            warn "Skipping #{entry.type} #{entry.name}: #{e.message}"
            next
          end

          type = entry.type.to_s
          type_entries = (lock_entries[type] ||= {})
          type_entries[entry.name] = lock_entry
        end

        {
          "version"          => SCHEMA_VERSION,
          "homebrew_version" => HOMEBREW_VERSION,
          "entries"          => lock_entries,
        }
      end

      sig { params(value: T.untyped).returns(T.untyped) }
      private_class_method def self.deep_sort(value)
        case value
        when Hash
          value.to_h { |key, hash_value| [key.to_s, deep_sort(hash_value)] }.sort.to_h
        when Array
          value.map { |array_value| deep_sort(array_value) }
        else
          value
        end
      end
    end
  end
end
