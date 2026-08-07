# typed: strict
# frozen_string_literal: true

require "bundle/extensions/extension"

module Homebrew
  module Bundle
    class Cargo < Extension
      SourceOptions = T.type_alias { T::Hash[Symbol, String] }
      Crate = T.type_alias { { name: String, source: T.nilable(String) } }
      Checkable = T.type_alias { { name: String, options: SourceOptions } }
      CrateEntry = T.type_alias { T.any(Crate, Checkable) }

      # `cargo install --list` reports the origin of anything not installed from a
      # registry, as either a git URL or a local path. Only a git URL that resolves
      # from another machine is supported here, so neither a path nor the `file://`
      # scheme is accepted. `--git` rejects an scp-style remote, so a scheme is
      # required too.
      GIT_SOURCE_REGEX = %r{\A(?:ssh|git|https?)://}
      GIT_REFERENCE_KEYS = %w[branch tag rev].freeze
      PACKAGE_LIST_REGEX = /\A(?<name>[^\s:]+)\s+v[0-9A-Za-z.+-]+(?:\s+\((?<origin>[^)]+)\))?/

      class << self
        sig { override.returns(Symbol) }
        def type = :cargo

        sig { override.returns(String) }
        def check_label = "Cargo Package"

        sig { override.returns(String) }
        def banner_name = "Cargo packages"

        sig { override.params(name: String, options: Homebrew::Bundle::EntryInputOptions).returns(Dsl::Entry) }
        def entry(name, options = {})
          unknown_options = options.keys - [:source]
          raise "unknown options(#{unknown_options.inspect}) for cargo" if unknown_options.present?

          source = options.fetch(:source, nil)
          if !source.nil? && !source.is_a?(String)
            raise "options[:source](#{source.inspect}) should be a String object"
          end

          normalized_options = {}
          if source.present?
            normalized_source = normalize_source(source)
            raise "options[:source](#{source.inspect}) should be a git URL" if normalized_source.nil?

            selector = normalized_source.partition("?").last
            if selector.present? && GIT_REFERENCE_KEYS.exclude?(selector.partition("=").first)
              raise "options[:source](#{source.inspect}) should select a branch, tag or rev"
            end

            normalized_options[:source] = normalized_source
          end

          Dsl::Entry.new(:cargo, name, normalized_options)
        end

        sig { override.void }
        def reset!
          @packages = T.let(nil, T.nilable(T::Array[Crate]))
          @installed_packages = T.let(nil, T.nilable(T::Array[Crate]))
        end

        sig { override.returns(T.nilable(String)) }
        def cleanup_heading
          banner_name
        end

        sig { override.returns(String) }
        def package_manager_name
          "rust"
        end

        sig { override.returns(T.nilable(Pathname)) }
        def package_manager_executable
          which("cargo", ORIGINAL_PATHS)
        end

        sig { override.returns(T::Array[Crate]) }
        def packages
          packages = @packages
          return packages if packages

          @packages = if (cargo = package_manager_executable) &&
                         (!cargo.to_s.start_with?("/") || cargo.exist?)
            with_env(cargo_env(cargo)) do
              parse_package_list(`#{cargo} install --list`)
            end
          end
          return [] if @packages.nil?

          @packages
        end

        sig { override.params(package: Object).returns(String) }
        def dump_name(package)
          T.cast(package, CrateEntry)[:name]
        end

        sig { params(package: Object).returns(T.nilable(String)) }
        def dump_source(package)
          package = T.cast(package, CrateEntry)
          return package[:source] if package.key?(:source)

          package[:options].fetch(:source, nil)
        end

        sig { override.params(package: Object).returns(String) }
        def dump_entry(package)
          line = super
          source = dump_source(package)
          line = "#{line}, source: #{quote(source)}" if source.present?

          line
        end

        sig {
          override.params(
            name:    String,
            with:    T.nilable(T::Array[String]),
            source:  T.nilable(String),
            verbose: T::Boolean,
          ).returns(T::Boolean)
        }
        def install_package!(name, with: nil, source: nil, verbose: false)
          _ = with

          cargo = package_manager_executable!

          with_env(cargo_env(cargo)) do
            Bundle.system(cargo.to_s, "install", "--locked", *source_args(source), name, verbose:)
          end
        end

        sig { override.returns(T::Array[Crate]) }
        def installed_packages
          installed_packages = @installed_packages
          return installed_packages if installed_packages

          @installed_packages = packages.dup
        end

        sig { override.params(name: String, executable: Pathname).void }
        def uninstall_package!(name, executable: Pathname.new(""))
          Bundle.system(executable.to_s, "uninstall", name, verbose: false)
        end

        sig { override.params(executable: Pathname).returns(T::Hash[String, String]) }
        def package_manager_env(executable)
          cargo_env(executable)
        end

        sig {
          override.params(
            name:   String,
            with:   T.nilable(T::Array[String]),
            source: T.nilable(String),
          ).returns(Object)
        }
        def package_record(name, with: nil, source: nil)
          _ = with

          crate_record(name, source:)
        end

        sig { params(name: String, source: T.nilable(String)).returns(Crate) }
        def crate_record(name, source: nil)
          { name: name.strip, source: normalize_source(source) }
        end
        private :crate_record

        sig {
          override.params(
            name:   String,
            with:   T.nilable(T::Array[String]),
            source: T.nilable(String),
          ).returns(T::Boolean)
        }
        def package_installed?(name, with: nil, source: nil)
          installed_packages.include?(package_record(name, with:, source:))
        end

        sig {
          override.params(
            name:       String,
            with:       T.nilable(T::Array[String]),
            source:     T.nilable(String),
            no_upgrade: T::Boolean,
            verbose:    T::Boolean,
            _options:   Homebrew::Bundle::EntryOption,
          ).returns(T::Boolean)
        }
        def preinstall!(name, with: nil, source: nil, no_upgrade: false, verbose: false, **_options)
          _ = no_upgrade

          ensure_package_manager_installed!(name, verbose:)

          if package_installed?(name, with:, source:)
            puts "Skipping install of #{name} #{package_description}. It is already installed." if verbose
            return false
          end

          true
        end

        sig {
          override.params(
            name:       String,
            with:       T.nilable(T::Array[String]),
            source:     T.nilable(String),
            preinstall: T::Boolean,
            no_upgrade: T::Boolean,
            verbose:    T::Boolean,
            force:      T::Boolean,
            _options:   Homebrew::Bundle::EntryOption,
          ).returns(T::Boolean)
        }
        def install!(name, with: nil, source: nil, preinstall: true, no_upgrade: false, verbose: false, force: false,
                     **_options)
          _ = no_upgrade
          _ = force

          return true unless preinstall

          puts "Installing #{name} #{package_description}. It is not currently installed." if verbose
          return false unless install_package!(name, with:, source:, verbose:)

          package = crate_record(name, source:)
          installed_packages << package unless installed_packages.include?(package)
          packages << package unless packages.include?(package)
          true
        end

        # A branch, tag or revision selected at install time is reported by
        # `cargo install --list` as a URL query, and never more than one of them,
        # but `--git` rejects a query: it has to be passed as the matching flag.
        sig { params(source: T.nilable(String)).returns(T::Array[String]) }
        def source_args(source)
          source = normalize_source(source)
          return [] if source.nil?

          url, _, query = source.partition("?")
          key, _, value = query.partition("=")
          args = ["--git", url]
          args.push("--#{key}", value) if GIT_REFERENCE_KEYS.include?(key)

          args
        end
        private :source_args

        sig { params(output: String).returns(T::Array[Crate]) }
        def parse_package_list(output)
          output.lines.filter_map do |line|
            next if line.match?(/^\s/)

            match = line.match(PACKAGE_LIST_REGEX)
            next if match.nil?

            name = match[:name]
            next if name.nil?

            { name:, source: normalize_source(match[:origin]) }
          end.uniq
        end
        private :parse_package_list

        # The resolved revision that `cargo install --list` appends to a git origin
        # is deliberately dropped: a dumped Brewfile has to compare equal to a
        # hand-written one, which a pinned revision would prevent. Anything that is
        # not a git URL has no `source:` to dump, whether it is a registry crate or
        # a local path.
        sig { params(source: T.nilable(String)).returns(T.nilable(String)) }
        def normalize_source(source)
          source = source.presence&.strip&.sub(/#[^#]*\z/, "")
          return if source.blank?
          return source if source.match?(GIT_SOURCE_REGEX)

          nil
        end
        private :normalize_source

        sig { params(cargo: Pathname).returns(T::Hash[String, String]) }
        def cargo_env(cargo)
          {
            "CARGO_HOME"         => ENV.fetch("HOMEBREW_CARGO_HOME", nil),
            "CARGO_INSTALL_ROOT" => ENV.fetch("HOMEBREW_CARGO_INSTALL_ROOT", nil),
            "PATH"               => "#{cargo.dirname}:#{ENV.fetch("PATH")}",
            "RUSTUP_HOME"        => ENV.fetch("HOMEBREW_RUSTUP_HOME", nil),
          }.compact
        end
        private :cargo_env
      end

      sig { override.params(entries: T::Array[Dsl::Entry]).returns(T::Array[Object]) }
      def format_checkable(entries)
        checkable_entries(entries).map do |entry|
          { name: entry.name, options: entry.options }
        end
      end

      sig { override.params(package: Object, no_upgrade: T::Boolean).returns(T::Boolean) }
      def installed_and_up_to_date?(package, no_upgrade: false)
        self.class.package_installed?(
          self.class.dump_name(package),
          source: self.class.dump_source(package),
        )
      end
    end
  end
end
