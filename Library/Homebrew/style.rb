# typed: strict
# frozen_string_literal: true

require "shellwords"
require "source_location"
require "stringio"
require "system_command"
require "tap"
require "utils/output"

module Homebrew
  # Helper module for running RuboCop.
  module Style
    extend Utils::Output::Mixin
    extend SystemCommand::Mixin

    # Checks style for a list of files, printing simple RuboCop output.
    # Returns true if violations were found, false otherwise.
    sig { params(files: T::Array[Pathname], options: T.untyped).returns(T::Boolean) }
    def self.check_style_and_print(files, **options)
      success = check_style_impl(files, :print, **options)

      if GitHub::Actions.env_set? && !success
        check_style_json(files, **options).each do |path, offenses|
          offenses.each do |o|
            line = o.location.line
            column = o.location.line

            annotation = GitHub::Actions::Annotation.new(:error, o.message, file: path, line:, column:)
            puts annotation if annotation.relevant?
          end
        end
      end

      T.cast(success, T::Boolean)
    end

    # Checks style for a list of files, returning results as an {Offenses}
    # object parsed from its JSON output.
    sig { params(files: T::Array[Pathname], options: T.untyped).returns(Offenses) }
    def self.check_style_json(files, **options)
      T.cast(check_style_impl(files, :json, **options), Offenses)
    end

    sig {
      params(
        files:             T::Array[Pathname],
        output_type:       Symbol,
        fix:               T::Boolean,
        todo:              T::Boolean,
        except_cops:       T.nilable(T::Array[String]),
        only_cops:         T.nilable(T::Array[String]),
        display_cop_names: T::Boolean,
        reset_cache:       T::Boolean,
        debug:             T::Boolean,
        verbose:           T::Boolean,
      ).returns(T.any(Offenses, T::Boolean))
    }
    def self.check_style_impl(files, output_type,
                              fix: false,
                              todo: false,
                              except_cops: nil, only_cops: nil,
                              display_cop_names: false,
                              reset_cache: false,
                              debug: false, verbose: false)
      raise ArgumentError, "Invalid output type: #{output_type.inspect}" if [:print, :json].exclude?(output_type)

      ruby_files = T.let([], T::Array[Pathname])
      shell_files = T.let([], T::Array[Pathname])
      actionlint_files = T.let([], T::Array[Pathname])
      Array(files).map { Pathname(it) }
                  .each do |path|
        case path.extname
        when ".rb"
          ruby_files << path
        when ".sh"
          shell_files << path
        when ".yml"
          actionlint_files << path if path.realpath.to_s.include?("/.github/workflows/")
        else
          ruby_files << path
          shell_files += if [HOMEBREW_PREFIX, HOMEBREW_REPOSITORY].include?(path)
            shell_scripts
          else
            path.glob("**/*.sh")
                .reject { |file_path| file_path.to_s.include?("/vendor/") || file_path.directory? }
          end
          actionlint_files += (path/".github/workflows").glob("*.y{,a}ml")
        end
      end

      rubocop_needed = files.blank? || ruby_files.any?
      shell_needed = files.blank? || shell_files.any?

      actionlint_files = github_workflow_files if files.blank? && actionlint_files.blank?
      has_actionlint_workflow = actionlint_files.any? do |path|
        path.to_s.end_with?("/.github/workflows/actionlint.yml")
      end
      odebug "actionlint workflow detected. Skipping actionlint checks." if has_actionlint_workflow
      actionlint_needed = files.blank? || (!has_actionlint_workflow && actionlint_files.any?)

      # Resolve the linter executables (installing them if necessary) before
      # spawning threads so those threads cannot race to install formulae.
      shellcheck_path = (shellcheck if shell_needed || actionlint_needed)
      shfmt_path = (shfmt_executable if shell_needed)
      actionlint_path = (actionlint if actionlint_needed)

      shellcheck_out = StringIO.new
      shellcheck_err = StringIO.new
      shfmt_out = StringIO.new
      shfmt_err = StringIO.new
      actionlint_out = StringIO.new
      actionlint_err = StringIO.new

      # Run the shell and GitHub Actions checks on background threads with
      # buffered output while RuboCop runs on the main thread.
      shell_thread = Thread.new do
        shellcheck_result = if shell_needed
          run_shellcheck(shell_files, output_type, fix:, shellcheck_path:,
                         out: shellcheck_out, err: shellcheck_err)
        elsif output_type == :json
          []
        else
          true
        end
        # `shellcheck --fix` and `shfmt --write` may touch the same files so
        # they must not run concurrently with each other.
        shfmt_result = !shell_needed || run_shfmt!(shell_files, fix:, shfmt_path:,
                                                   out: shfmt_out, err: shfmt_err)
        [shellcheck_result, shfmt_result]
      end
      actionlint_thread = Thread.new do
        !actionlint_needed ||
          run_actionlint!(actionlint_files, actionlint_path:, shellcheck_path:,
                          out: actionlint_out, err: actionlint_err)
      end

      rubocop_result = if rubocop_needed
        run_rubocop(ruby_files, output_type,
                    fix:,
                    todo:,
                    except_cops:, only_cops:,
                    display_cop_names:,
                    reset_cache:,
                    debug:, verbose:)
      elsif output_type == :json
        []
      else
        true
      end

      shellcheck_result, shfmt_result = shell_thread.value
      actionlint_result = actionlint_thread.value

      [
        [shellcheck_out, shellcheck_err],
        [shfmt_out, shfmt_err],
        [actionlint_out, actionlint_err],
      ].each do |out, err|
        $stdout.print out.string
        $stderr.print err.string
      end

      if output_type == :json
        Offenses.new(
          T.cast(rubocop_result, T::Array[T::Hash[String, T.untyped]]) +
          T.cast(shellcheck_result, T::Array[T::Hash[String, T.untyped]]),
        )
      else
        rubocop_result && !!shellcheck_result && shfmt_result && actionlint_result
      end
    end

    RUBOCOP = T.let((HOMEBREW_LIBRARY_PATH/"utils/rubocop.rb").freeze, Pathname)

    sig {
      params(
        files:             T::Array[Pathname],
        output_type:       Symbol,
        fix:               T::Boolean,
        todo:              T::Boolean,
        except_cops:       T.nilable(T::Array[String]),
        only_cops:         T.nilable(T::Array[String]),
        display_cop_names: T::Boolean,
        reset_cache:       T::Boolean,
        debug:             T::Boolean,
        verbose:           T::Boolean,
      ).returns(T.any(T::Boolean, T::Array[T::Hash[String, T.untyped]]))
    }
    def self.run_rubocop(files, output_type,
                         fix: false, todo: false, except_cops: nil, only_cops: nil, display_cop_names: false,
                         reset_cache: false,
                         debug: false, verbose: false)
      require "warnings"

      Warnings.ignore :parser_syntax do
        require "rubocop"
      end

      require "rubocops/all"

      args = %w[
        --force-exclusion
      ]
      args << "--autocorrect-all" if fix
      args << "--disable-uncorrectable" if todo

      args += ["--extra-details"] if verbose

      if except_cops
        except_cops.map! { |cop| RuboCop::Cop::Registry.global.qualified_cop_name(cop.to_s, "") }
        cops_to_exclude = except_cops.select do |cop|
          RuboCop::Cop::Registry.global.names.include?(cop) ||
            RuboCop::Cop::Registry.global.departments.include?(cop.to_sym)
        end

        args << "--except" << cops_to_exclude.join(",") unless cops_to_exclude.empty?
      elsif only_cops
        only_cops.map! { |cop| RuboCop::Cop::Registry.global.qualified_cop_name(cop.to_s, "") }
        cops_to_include = only_cops.select do |cop|
          RuboCop::Cop::Registry.global.names.include?(cop) ||
            RuboCop::Cop::Registry.global.departments.include?(cop.to_sym)
        end

        odie "RuboCops #{only_cops.join(",")} were not found" if cops_to_include.empty?

        args << "--only" << cops_to_include.join(",")
      end

      files.map!(&:expand_path)
      base_dir = Dir.pwd
      if files.blank? || files == [HOMEBREW_REPOSITORY]
        files = [HOMEBREW_LIBRARY_PATH]
        base_dir = HOMEBREW_LIBRARY_PATH
      elsif files.any? { |f| f.to_s.start_with?(HOMEBREW_REPOSITORY/"docs") || (f.basename.to_s == "docs") }
        args << "--config" << (HOMEBREW_REPOSITORY/"docs/docs_rubocop_style.yml")
      elsif files.any? { |f| f.to_s.start_with? HOMEBREW_LIBRARY_PATH }
        base_dir = HOMEBREW_LIBRARY_PATH
      else
        args << "--config" << (HOMEBREW_LIBRARY/".rubocop.yml")
        base_dir = HOMEBREW_LIBRARY if files.any? { |f| f.to_s.start_with? HOMEBREW_LIBRARY }
      end

      HOMEBREW_CACHE.mkpath
      cache_dir = HOMEBREW_CACHE.realpath/"style"
      cache_env = if (!cache_dir.exist? && cache_dir.parent.writable?) || cache_dir.writable?
        args << "--parallel"

        FileUtils.rm_rf cache_dir if reset_cache

        { "XDG_CACHE_HOME" => cache_dir.to_s }
      else
        args << "--cache" << "false"

        {}
      end

      args += files

      ruby_args = HOMEBREW_RUBY_EXEC_ARGS.dup
      case output_type
      when :print
        args << "--debug" if debug

        # Don't show the default formatter's progress dots
        # on CI or if only checking a single file.
        args << "--format" << "clang" if ENV["CI"] || files.one? { |f| !f.directory? }

        args << "--color" if Tty.color?

        system cache_env, *ruby_args, "--", RUBOCOP, *args, chdir: base_dir
        $CHILD_STATUS.success?
      when :json
        result = system_command ruby_args.shift,
                                args:  [*ruby_args, "--", RUBOCOP, "--format", "json", *args],
                                env:   cache_env,
                                chdir: base_dir
        json = json_result!(result)
        json["files"].each do |file|
          file["path"] = File.absolute_path(file["path"], base_dir)
        end
      end
    end

    sig {
      params(
        files:           T::Array[Pathname],
        output_type:     Symbol,
        fix:             T::Boolean,
        shellcheck_path: T.nilable(Pathname),
        out:             T.any(IO, StringIO),
        err:             T.any(IO, StringIO),
      ).returns(T.nilable(T.any(T::Boolean, T::Array[T::Hash[String, T.untyped]])))
    }
    def self.run_shellcheck(files, output_type, fix: false, shellcheck_path: nil, out: $stdout, err: $stderr)
      shellcheck_path ||= shellcheck
      files = shell_scripts if files.blank?

      files = files.map(&:realpath) # use absolute file paths

      args = [
        "--shell=bash",
        "--enable=all",
        "--external-sources",
        "--source-path=#{HOMEBREW_LIBRARY}",
      ]

      if fix
        # patch options:
        #   -g 0 (--get=0)       : suppress environment variable `PATCH_GET`
        #   -f   (--force)       : we know what we are doing, force apply patches
        #   -d / (--directory=/) : change to root directory, since we use absolute file paths
        #   -p0  (--strip=0)     : do not strip path prefixes, since we are at root directory
        # NOTE: We use short flags for compatibility.
        patch_command = %w[patch -g 0 -f -d / -p0]
        patches = shellcheck_chunks(shellcheck_path, files, ["--format=diff", *args]).map(&:stdout).join
        Utils.safe_popen_write(*patch_command) { |p| p.write(patches) } if patches.present?
      end

      case output_type
      when :print
        print_args = ["--format=tty", *args]
        print_args << "--color=always" if Tty.color?
        results = shellcheck_chunks(shellcheck_path, files, print_args)
        results.each do |result|
          out.print result.stdout
          err.print result.stderr
        end
        results.all?(&:success?)
      when :json
        results = shellcheck_chunks(shellcheck_path, files, ["--format=json", *args])
        json = results.flat_map { |result| json_result!(result) }

        # Convert to same format as RuboCop offenses.
        severity_hash = { "style" => "refactor", "info" => "convention" }
        json.group_by { |v| v["file"] }
            .map do |k, v|
          {
            "path"     => k,
            "offenses" => v.map do |o|
              o.delete("file")

              o["cop_name"] = "SC#{o.delete("code")}"

              level = o.delete("level")
              o["severity"] = severity_hash.fetch(level, level)

              line = o.delete("line")
              column = o.delete("column")

              o["corrected"] = false
              o["correctable"] = o.delete("fix").present?

              o["location"] = {
                "start_line"   => line,
                "start_column" => column,
                "last_line"    => o.delete("endLine"),
                "last_column"  => o.delete("endColumn"),
                "line"         => line,
                "column"       => column,
              }

              o
            end,
          }
        end
      end
    end

    sig {
      params(
        shellcheck_path: Pathname,
        files:           T::Array[Pathname],
        args:            T::Array[String],
      ).returns(T::Array[SystemCommand::Result])
    }
    private_class_method def self.shellcheck_chunks(shellcheck_path, files, args)
      require "hardware"

      chunk_count = [Hardware::CPU.cores, files.length].min
      return [] if chunk_count.zero?

      files.each_slice((files.length.to_f / chunk_count).ceil).map do |chunk|
        Thread.new do
          system_command shellcheck_path, args: [*args, "--", *chunk], print_stderr: false
        end
      end.map(&:value)
    end

    sig {
      params(
        files:      T::Array[Pathname],
        fix:        T::Boolean,
        shfmt_path: T.nilable(Pathname),
        out:        T.any(IO, StringIO),
        err:        T.any(IO, StringIO),
      ).returns(T::Boolean)
    }
    def self.run_shfmt!(files, fix: false, shfmt_path: nil, out: $stdout, err: $stderr)
      shfmt_path ||= shfmt_executable
      files = shell_scripts if files.blank?
      # Do not format completions and Dockerfile
      files.delete(HOMEBREW_REPOSITORY/"completions/bash/brew")
      files.delete(HOMEBREW_REPOSITORY/"Dockerfile")

      args = ["--language-dialect", "bash", "--indent", "2", "--case-indent", "--", *files]
      args.unshift("--write") if fix # need to add before "--"

      result = system_command shfmt,
                              args:,
                              env:          { "HOMEBREW_SHFMT" => shfmt_path.to_s },
                              print_stderr: false
      out.print result.stdout
      err.print result.stderr
      result.success?
    end

    sig {
      params(
        files:           T::Array[Pathname],
        actionlint_path: T.nilable(Pathname),
        shellcheck_path: T.nilable(Pathname),
        out:             T.any(IO, StringIO),
        err:             T.any(IO, StringIO),
      ).returns(T::Boolean)
    }
    def self.run_actionlint!(files, actionlint_path: nil, shellcheck_path: nil, out: $stdout, err: $stderr)
      actionlint_path ||= actionlint
      shellcheck_path ||= shellcheck
      files = github_workflow_files if files.blank?

      tap_configs = files.filter_map do |f|
        tap = Tap.from_path(f)
        next unless tap

        tap_config = tap.path/".github/actionlint.yaml"
        tap_config if tap_config.exist?
      end.uniq

      config_file = if tap_configs.one?
        tap_configs.fetch(0)
      else
        HOMEBREW_REPOSITORY/".github/actionlint.yaml"
      end

      # the ignore is to avoid false positives in e.g. actions, homebrew-test-bot
      args = ["-shellcheck", shellcheck_path,
              "-config-file", config_file,
              "-ignore", "image: string; options: string",
              "-ignore", "label .* is unknown"]
      args << "-color" if Tty.color?
      result = system_command actionlint_path, args: [*args, *files], print_stderr: false
      out.print result.stdout
      err.print result.stderr
      result.success?
    end

    sig { params(result: SystemCommand::Result).returns(T.untyped) }
    def self.json_result!(result)
      # An exit status of 1 just means violations were found; other numbers mean
      # execution errors.
      # JSON needs to be at least 2 characters.
      result.assert_success! if !(0..1).cover?(result.status.exitstatus) || result.stdout.length < 2

      JSON.parse(result.stdout)
    end

    sig { returns(T::Array[Pathname]) }
    def self.shell_scripts
      [
        HOMEBREW_ORIGINAL_BREW_FILE.realpath,
        HOMEBREW_REPOSITORY/"completions/bash/brew",
        HOMEBREW_REPOSITORY/"Dockerfile",
        *HOMEBREW_REPOSITORY.glob(".devcontainer/**/*.sh"),
        *HOMEBREW_REPOSITORY.glob(".github/scripts/*.sh"),
        *HOMEBREW_REPOSITORY.glob("package/scripts/*"),
        *HOMEBREW_LIBRARY.glob("Homebrew/**/*.sh").reject { |path| path.to_s.include?("/vendor/") },
        *HOMEBREW_LIBRARY.glob("Homebrew/shims/**/*").map(&:realpath).uniq
                         .reject(&:directory?)
                         .reject { |path| path.basename.to_s == "cc" }
                         .select do |path|
                           %r{^#! ?/bin/(?:ba)?sh( |$)}.match?(path.read(13))
                         end,
        *HOMEBREW_LIBRARY.glob("Homebrew/{dev-,}cmd/*.sh"),
        *HOMEBREW_LIBRARY.glob("Homebrew/{cask/,}utils/*.sh"),
      ]
    end

    sig { returns(T::Array[Pathname]) }
    def self.github_workflow_files
      HOMEBREW_REPOSITORY.glob(".github/workflows/*.yml")
    end

    sig { returns(Pathname) }
    def self.shellcheck
      require "formula"
      T.cast(Formula["shellcheck"].ensure_installed!(latest:     true,
                                                     reason:     "shell style checks",
                                                     executable: "shellcheck"), Pathname)
    end

    sig { returns(Pathname) }
    def self.shfmt
      HOMEBREW_LIBRARY/"Homebrew/utils/shfmt.sh"
    end

    sig { returns(Pathname) }
    private_class_method def self.shfmt_executable
      require "formula"
      T.cast(Formula["shfmt"].ensure_installed!(latest:     true,
                                                reason:     "formatting shell scripts",
                                                executable: "shfmt"), Pathname)
    end

    sig { returns(Pathname) }
    def self.actionlint
      require "formula"
      T.cast(Formula["actionlint"].ensure_installed!(latest:       true,
                                                     reason:       "GitHub Actions checks",
                                                     executable:   "actionlint",
                                                     version_args: ["-version"]), Pathname)
    end

    # Collection of style offenses.
    class Offenses
      include Enumerable
      extend T::Generic

      Elem = type_member(:out) { { fixed: Offense } }

      sig { params(paths: T::Array[T::Hash[String, T.untyped]]).void }
      def initialize(paths)
        @offenses = T.let({}, T::Hash[Pathname, T::Array[Offense]])
        paths.each do |f|
          next if f["offenses"].empty?

          path = Pathname(f["path"]).realpath
          @offenses[path] = f["offenses"].map { |x| Offense.new(x) }
        end
      end

      sig { params(path: T.any(String, Pathname)).returns(T::Array[Offense]) }
      def for_path(path)
        @offenses.fetch(Pathname(path), [])
      end

      # `Enumerable#each` has a generic block type incompatible with the specific
      # `[Pathname, T::Array[Offense]]` pairs this Hash-backed class yields.
      # rubocop:disable Sorbet/AllowIncompatibleOverride
      sig {
        override(allow_incompatible: true)
          .params(block: T.proc.params(arg0: [Pathname, T::Array[Homebrew::Style::Offense]]).returns(BasicObject))
          .returns(T.untyped)
      }
      # rubocop:enable Sorbet/AllowIncompatibleOverride
      def each(&block)
        @offenses.each(&block)
      end
    end

    # A style offense.
    class Offense
      sig { returns(String) }
      attr_reader :message

      sig { returns(T.nilable(String)) }
      attr_reader :severity, :cop_name

      sig { returns(T::Boolean) }
      attr_reader :corrected

      sig { returns(SourceLocation) }
      attr_reader :location

      sig { params(json: T::Hash[String, T.untyped]).void }
      def initialize(json)
        @severity = T.let(json["severity"], T.nilable(String))
        @message = T.let(json.fetch("message"), String)
        @cop_name = T.let(json["cop_name"], T.nilable(String))
        @corrected = T.let(json["corrected"], T::Boolean)
        location = json.fetch("location")
        @location = T.let(SourceLocation.new(location.fetch("line"), location["column"]), SourceLocation)
      end

      sig { returns(T::Boolean) }
      def corrected?
        @corrected
      end
    end
  end
end
