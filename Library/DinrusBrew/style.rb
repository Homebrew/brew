# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

require "shellwords"
require "source_location"
require "system_command"

module DinrusBrew
  # Helper module for running RuboCop.
  module Style
    extend SystemCommand::Mixin

    # Checks style for a list of files, printing simple RuboCop output.
    # Returns true if violations were found, false otherwise.
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

      success
    end

    # Checks style for a list of files, returning results as an {Offenses}
    # object parsed from its JSON output.
    def self.check_style_json(files, **options)
      check_style_impl(files, :json, **options)
    end

    def self.check_style_impl(files, output_type,
                              fix: false,
                              except_cops: nil, only_cops: nil,
                              display_cop_names: false,
                              reset_cache: false,
                              debug: false, verbose: false)
      raise ArgumentError, "Неполноценный тип вывода: #{output_type.inspect}" if [:print, :json].exclude?(output_type)

      ruby_files = T.let([], T::Array[Pathname])
      shell_files = T.let([], T::Array[Pathname])
      actionlint_files = T.let([], T::Array[Pathname])
      Array(files).map(&method(:Pathname))
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
          shell_files += if [DINRUSBREW_PREFIX, DINRUSBREW_REPOSITORY].include?(path)
            shell_scripts
          else
            path.glob("**/*.sh")
                .reject { |path| path.to_s.include?("/vendor/") || path.directory? }
          end
          actionlint_files += (path/".github/workflows").glob("*.y{,a}ml")
        end
      end

      rubocop_result = if files.present? && ruby_files.empty?
        (output_type == :json) ? [] : true
      else
        run_rubocop(ruby_files, output_type,
                    fix:,
                    except_cops:, only_cops:,
                    display_cop_names:,
                    reset_cache:,
                    debug:, verbose:)
      end

      shellcheck_result = if files.present? && shell_files.empty?
        (output_type == :json) ? [] : true
      else
        run_shellcheck(shell_files, output_type, fix:)
      end

      shfmt_result = if files.present? && shell_files.empty?
        true
      else
        run_shfmt(shell_files, fix:)
      end

      has_actionlint_workflow = actionlint_files.any? do |path|
        path.to_s.end_with?("/.github/workflows/actionlint.yml")
      end
      odebug "actionlint workflow detected. Skipping actionlint checks." if has_actionlint_workflow
      actionlint_result = if files.present? && (has_actionlint_workflow || actionlint_files.empty?)
        true
      else
        run_actionlint(actionlint_files)
      end

      if output_type == :json
        Offenses.new(rubocop_result + shellcheck_result)
      else
        rubocop_result && shellcheck_result && shfmt_result && actionlint_result
      end
    end

    RUBOCOP = (DINRUSBREW_LIBRARY_PATH/"utils/rubocop.rb").freeze

    def self.run_rubocop(files, output_type,
                         fix: false, except_cops: nil, only_cops: nil, display_cop_names: false, reset_cache: false,
                         debug: false, verbose: false)
      require "warnings"

      Warnings.ignore :parser_syntax do
        require "rubocop"
      end

      require "rubocops/all"

      args = %w[
        --force-exclusion
      ]
      args << if fix
        "--autocorrect-all"
      else
        "--parallel"
      end

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

        odie "RuboCops #{only_cops.join(",")} не найдены" if cops_to_include.empty?

        args << "--only" << cops_to_include.join(",")
      end

      files&.map!(&:expand_path)
      base_dir = Dir.pwd
      if files.blank? || files == [DINRUSBREW_REPOSITORY]
        files = [DINRUSBREW_LIBRARY_PATH]
        base_dir = DINRUSBREW_LIBRARY_PATH
      elsif files.any? { |f| f.to_s.start_with?(DINRUSBREW_REPOSITORY/"docs") || (f.basename.to_s == "docs") }
        args << "--config" << (DINRUSBREW_REPOSITORY/"docs/docs_rubocop_style.yml")
      elsif files.any? { |f| f.to_s.start_with? DINRUSBREW_LIBRARY_PATH }
        base_dir = DINRUSBREW_LIBRARY_PATH
      else
        args << "--config" << (DINRUSBREW_LIBRARY/".rubocop.yml")
        base_dir = DINRUSBREW_LIBRARY if files.any? { |f| f.to_s.start_with? DINRUSBREW_LIBRARY }
      end

      args += files

      DINRUSBREW_CACHE.mkpath
      cache_dir = DINRUSBREW_CACHE.realpath
      cache_env = { "XDG_CACHE_HOME" => "#{cache_dir}/style" }

      FileUtils.rm_rf cache_env["XDG_CACHE_HOME"] if reset_cache

      ruby_args = DINRUSBREW_RUBY_EXEC_ARGS.dup
      case output_type
      when :print
        args << "--debug" if debug

        # Don't show the default formatter's progress dots
        # on CI or if only checking a single file.
        args << "--format" << "clang" if ENV["CI"] || files.count { |f| !f.directory? } == 1

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

    def self.run_shellcheck(files, output_type, fix: false)
      files = shell_scripts if files.blank?

      files = files.map(&:realpath) # use absolute file paths

      args = [
        "--shell=bash",
        "--enable=all",
        "--external-sources",
        "--source-path=#{DINRUSBREW_LIBRARY}",
        "--",
        *files,
      ]

      if fix
        # patch options:
        #   -g 0 (--get=0)       : suppress environment variable `PATCH_GET`
        #   -f   (--force)       : we know what we are doing, force apply patches
        #   -d / (--directory=/) : change to root directory, since we use absolute file paths
        #   -p0  (--strip=0)     : do not strip path prefixes, since we are at root directory
        # NOTE: We use short flags for compatibility.
        patch_command = %w[patch -g 0 -f -d / -p0]
        patches = system_command(shellcheck, args: ["--format=diff", *args]).stdout
        Utils.safe_popen_write(*patch_command) { |p| p.write(patches) } if patches.present?
      end

      case output_type
      when :print
        system shellcheck, "--format=tty", *args
        $CHILD_STATUS.success?
      when :json
        result = system_command shellcheck, args: ["--format=json", *args]
        json = json_result!(result)

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

    def self.run_shfmt(files, fix: false)
      files = shell_scripts if files.blank?
      # Do not format completions and Dockerfile
      files.delete(DINRUSBREW_REPOSITORY/"completions/bash/brew")
      files.delete(DINRUSBREW_REPOSITORY/"Dockerfile")

      args = ["--language-dialect", "bash", "--indent", "2", "--case-indent", "--", *files]
      args.unshift("--write") if fix # need to add before "--"

      system shfmt, *args
      $CHILD_STATUS.success?
    end

    def self.run_actionlint(files)
      files = github_workflow_files if files.blank?
      # the ignore is to avoid false positives in e.g. actions, homebrew-test-bot
      system actionlint, "-shellcheck", shellcheck,
             "-config-file", DINRUSBREW_REPOSITORY/".github/actionlint.yaml",
             "-ignore", "image: string; options: string",
             "-ignore", "label .* is unknown",
             *files
      $CHILD_STATUS.success?
    end

    def self.json_result!(result)
      # An exit status of 1 just means violations were found; other numbers mean
      # execution errors.
      # JSON needs to be at least 2 characters.
      result.assert_success! if !(0..1).cover?(result.status.exitstatus) || result.stdout.length < 2

      JSON.parse(result.stdout)
    end

    def self.shell_scripts
      [
        DINRUSBREW_ORIGINAL_BREW_FILE,
        DINRUSBREW_REPOSITORY/"completions/bash/brew",
        DINRUSBREW_REPOSITORY/"Dockerfile",
        *DINRUSBREW_REPOSITORY.glob(".devcontainer/**/*.sh"),
        *DINRUSBREW_REPOSITORY.glob("package/scripts/*"),
        *DINRUSBREW_LIBRARY.glob("DinrusBrew/**/*.sh").reject { |path| path.to_s.include?("/vendor/") },
        *DINRUSBREW_LIBRARY.glob("DinrusBrew/shims/**/*").map(&:realpath).uniq
                         .reject(&:directory?)
                         .reject { |path| path.basename.to_s == "cc" }
                         .select do |path|
                           %r{^#! ?/bin/(?:ba)?sh( |$)}.match?(path.read(13))
                         end,
        *DINRUSBREW_LIBRARY.glob("DinrusBrew/{dev-,}cmd/*.sh"),
        *DINRUSBREW_LIBRARY.glob("DinrusBrew/{cask/,}utils/*.sh"),
      ]
    end

    def self.github_workflow_files
      DINRUSBREW_REPOSITORY.glob(".github/workflows/*.yml")
    end

    def self.rubocop
      ensure_formula_installed!("rubocop", latest: true,
                                           reason: "Ruby style checks").opt_bin/"rubocop"
    end

    def self.shellcheck
      ensure_formula_installed!("shellcheck", latest: true,
                                              reason: "shell style checks").opt_bin/"shellcheck"
    end

    def self.shfmt
      ensure_formula_installed!("shfmt", latest: true,
                                         reason: "formatting shell scripts")
      DINRUSBREW_LIBRARY/"DinrusBrew/utils/shfmt.sh"
    end

    def self.actionlint
      ensure_formula_installed!("actionlint", latest: true,
                                              reason: "GitHub Actions checks").opt_bin/"actionlint"
    end

    # Collection of style offenses.
    class Offenses
      include Enumerable

      def initialize(paths)
        @offenses = {}
        paths.each do |f|
          next if f["offenses"].empty?

          path = Pathname(f["path"]).realpath
          @offenses[path] = f["offenses"].map { |x| Offense.new(x) }
        end
      end

      def for_path(path)
        @offenses.fetch(Pathname(path), [])
      end

      def each(*args, &block)
        @offenses.each(*args, &block)
      end
    end

    # A style offense.
    class Offense
      attr_reader :severity, :message, :corrected, :location, :cop_name

      def initialize(json)
        @severity = json["severity"]
        @message = json["message"]
        @cop_name = json["cop_name"]
        @corrected = json["corrected"]
        location = json["location"]
        @location = SourceLocation.new(location.fetch("line"), location["column"])
      end

      def severity_code
        @severity[0].upcase
      end

      def corrected?
        @corrected
      end
    end
  end
end
