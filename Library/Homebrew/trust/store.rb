# typed: strict
# frozen_string_literal: true

require "etc"
require "json"

module Homebrew
  module Trust
    # Secure, locked persistence for trust decisions.
    module Store
      extend T::Helpers

      requires_ancestor { T.class_of(Trust) }

      sig { params(home: T.nilable(T.any(String, Pathname))).returns(Pathname) }
      def trust_file(home: nil)
        user = ENV.fetch("USER")
        user_home = Pathname.new begin
          Dir.home(user)
        rescue ArgumentError
          fallback_home = Dir.home
          opoo "Could not determine home directory for `$USER` (#{user}); falling back to #{fallback_home}."
          fallback_home
        end
        home ||= user_home
        user_config_home = Pathname.new(ENV.fetch("HOMEBREW_USER_CONFIG_HOME"))
        if user_config_home == user_home/".homebrew"
          Pathname.new(home.to_s)/".homebrew/trust.json"
        else
          user_config_home/"trust.json"
        end
      end

      sig { returns(T::Hash[String, T::Array[String]]) }
      def trust_store
        trust_path = if Homebrew.running_as_root? &&
                        (sudo_user = ENV.fetch("HOMEBREW_SUDO_USER", nil).presence) &&
                        sudo_user != "root"
          passwd = begin
            Etc.getpwnam(sudo_user)
          rescue ArgumentError
            nil
          end

          if passwd
            trust_file(home: passwd.dir)
          else
            opoo "Could not determine home directory for `$HOMEBREW_SUDO_USER` (#{sudo_user}); " \
                 "falling back to #{trust_file}."
            trust_file
          end
        else
          trust_file
        end
        return {} unless trust_path.exist?

        parsed_store = JSON.parse(trust_path.read)
        return {} unless parsed_store.is_a?(Hash)

        parsed_store.transform_values { |entries| Array(entries).map { |entry| normalise_name(entry.to_s) } }
      rescue Errno::ENOENT, JSON::ParserError
        {}
      end
      private :trust_store

      sig { params(store: T::Hash[String, T::Array[String]]).void }
      def write_trust_store(store)
        write_path = trust_file
        if write_path.symlink?
          link_parent = write_path.dirname.realpath
          assert_secure_trust_store_path!(link_parent, link_parent.stat, "symlink directory")
          if write_path.lstat.uid != Process.euid
            raise InsecureTrustStoreError,
                  "Refusing to write insecure trust store: symlink #{write_path} is not owned by the current user."
          end
          target_path = write_path.readlink
          target_path = write_path.dirname/target_path unless target_path.absolute?
          target_parent = target_path.dirname.realpath
          assert_secure_trust_store_path!(target_parent, target_parent.stat, "target directory")
          write_path = target_parent/target_path.basename
          if write_path.symlink?
            raise InsecureTrustStoreError,
                  "Refusing to write insecure trust store: target is a symlink."
          end
          if write_path.exist?
            assert_secure_trust_store_path!(write_path, write_path.stat, "target")
            unless write_path.file?
              raise InsecureTrustStoreError,
                    "Refusing to write insecure trust store: target is not a regular file."
            end
          end
        else
          ensure_secure_trust_store_directory!(write_path.dirname, "trust store directory")
          if write_path.exist?
            assert_secure_trust_store_path!(write_path, write_path.stat, "trust store")
            unless write_path.file?
              raise InsecureTrustStoreError,
                    "Refusing to write insecure trust store: trust store is not a regular file."
            end
          end
        end
        if store.empty?
          write_path.unlink if write_path.exist?
          return
        end

        write_path.atomic_write("#{JSON.pretty_generate(store)}\n")
        write_path.chmod(0600)
      rescue Errno::ENOENT
        raise InsecureTrustStoreError, "Refusing to write insecure trust store: target directory does not exist."
      end
      private :write_trust_store

      sig { params(path: Pathname, description: String).void }
      def ensure_secure_trust_store_directory!(path, description)
        existed = path.exist?
        path.mkpath
        path.chmod(0700) unless existed
        assert_secure_trust_store_path!(path, path.stat, description)
      end
      private :ensure_secure_trust_store_directory!

      sig { params(path: Pathname, stat: File::Stat, description: String).void }
      def assert_secure_trust_store_path!(path, stat, description)
        if stat.uid != Process.euid
          raise InsecureTrustStoreError,
                "Refusing to write insecure trust store: #{description} #{path} is not owned by the current user."
        end

        return if stat.mode.nobits?(022)

        raise InsecureTrustStoreError,
              "Refusing to write insecure trust store: #{description} #{path} is group or world writable."
      end
      private :assert_secure_trust_store_path!

      # Serialises trust store mutations so concurrent processes or threads
      # (e.g. parallel `brew bundle` installs) cannot lose entries in the
      # read-modify-write cycle.
      sig {
        type_parameters(:U).params(_block: T.proc.returns(T.type_parameter(:U))).returns(T.type_parameter(:U))
      }
      def with_trust_store_lock(&_block)
        lock_path = Pathname.new("#{trust_file}.lock")
        ensure_secure_trust_store_directory!(lock_path.dirname, "trust store directory")
        File.open(lock_path, File::RDWR | File::CREAT, 0600) do |lock_file|
          lock_file.flock(File::LOCK_EX)
          yield
        end
      end
      private :with_trust_store_lock
    end
  end
end
