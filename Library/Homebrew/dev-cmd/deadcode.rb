# typed: strict
# frozen_string_literal: true

require "abstract_command"

module Homebrew
  module DevCmd
    class Deadcode < AbstractCommand
      # Spoom's default excludes plus `test/` so that definitions only
      # referenced by their specs are still reported as dead. `--exclude` takes
      # all values at once and replaces Spoom's defaults, so the defaults are
      # repeated here alongside `test/`.
      EXCLUDES = %w[vendor/ sorbet/ tmp/ log/ node_modules/ test/].freeze

      # Markers in the documentation or signature above a definition that keep
      # it: Spoom cannot see its dynamic, subclass or cross-tap (e.g.
      # homebrew-core) callers. Use `# deadcode:keep` for definitions that are
      # only reached dynamically (e.g. via `send`) and so are not part of any
      # API but must not be removed.
      PERSIST_REGEX = /^\s*#\s*@api\s+(?:public|internal)\b|^\s*#\s*deadcode:keep(?=\s|$)|\boverride\b/

      # Calls within a definition's body that keep it: a definition on its way
      # out via `odeprecated`/`odisabled` is intentionally retained through its
      # deprecation cycle even once its callers are gone.
      DEPRECATION_REGEX = /\bod(?:eprecated|isabled)\b/

      # A file-scoped directive (e.g. `# deadcode:keep-matching ^audit_`) that
      # keeps every definition whose name matches the pattern. Use it for whole
      # families of methods dispatched dynamically by naming convention, such as
      # `private_methods.grep(/^audit_/).each { |m| send(m) }`.
      KEEP_MATCHING_REGEX = /^\s*#\s*deadcode:keep-matching\s+(\S.*?)\s*$/

      # A command entry point: a subclass of `AbstractCommand`. These are
      # invoked by name (and `ShellCommand` ones are backed by Bash), so Spoom
      # sees no Ruby callers and reports the whole class as dead. Keep the class
      # definition itself; its methods and constants can still be removed.
      COMMAND_CLASS_REGEX = /\A\s*class\s+\w+\s*<\s*(?:\w+::)*AbstractCommand\b/

      # The `cmd/` and `dev-cmd/` directories (relative to `HOMEBREW_LIBRARY_PATH`,
      # where Spoom runs) holding those command entry points.
      COMMAND_PATH_REGEX = %r{(?:\A|/)(?:dev-)?cmd/[^/]+\.rb\z}

      cmd_args do
        description <<~EOS
          Find and remove dead code identified by Spoom. Test code is excluded
          from the analysis so that definitions only referenced by their tests
          are also treated as dead. Definitions documented with `# @api public`
          or `# @api internal`, defined with an `override` signature, marked
          with a `# deadcode:keep` (or file-scoped `# deadcode:keep-matching
          <pattern>`) comment, or deprecated with `odeprecated`/`odisabled`, are
          always kept, as are command classes (subclasses of `AbstractCommand`
          under `cmd/` or `dev-cmd/`).
        EOS
        switch "-n", "--dry-run",
               description: "List the dead code that would be removed without removing it."

        named_args :none
      end

      sig { override.void }
      def run
        Homebrew.install_bundler_gems!(groups: ["typecheck"])

        # Sorbet doesn't use bash privileged mode so we align EUID and UID here.
        Process::UID.change_privilege(Process.euid) if Process.euid != Process.uid

        HOMEBREW_LIBRARY_PATH.cd do
          locations = dead_code_locations
          if locations.empty?
            ohai "No dead code found!"
            return
          end

          kept, locations = locations.partition { |location| persisted?(location) }
          unless kept.empty?
            ohai "Keeping #{Utils.pluralize("definition", kept.count, include_count: true)} " \
                 "documented as `@api` or defined with `override`."
          end

          if locations.empty?
            ohai "No dead code left to remove."
            return
          end

          if args.dry_run?
            ohai "Dead code that would be removed:"
            locations.each { |location| puts "  #{location}" }
            return
          end

          remove(locations)
        end
      end

      private

      sig { returns(T::Array[String]) }
      def dead_code_locations
        spoom_exec = %w[bundle exec spoom deadcode --no-color --exclude] + EXCLUDES

        ohai "Searching for dead code with Spoom..."
        # Spoom exits non-zero when it finds candidates, so don't fail on that.
        # Candidates are printed to stderr, so merge it into the captured output.
        output = Utils.popen_read(*spoom_exec, err: :out)

        locations = output.lines.filter_map { |line| line[/\s(\S+:\d+:\d+-\d+:\d+)\s*$/, 1] }

        # Remove from the bottom of each file upwards so that removing one
        # location doesn't shift the line numbers of those still to be removed.
        locations.sort_by! do |location|
          file, line_column = location.split(":", 2)
          line, column = line_column.to_s.split(":", 2)
          [file.to_s, line.to_i, column.to_i]
        end
        locations.reverse!
        locations
      end

      sig { params(location: String).returns(T::Boolean) }
      def persisted?(location)
        # Locations are `file:start_line:start_col-end_line:end_col`.
        file, positions = location.split(":", 2)
        return false if file.nil? || positions.nil?

        start_line = positions[/\A(\d+)/, 1].to_i
        end_line = positions[/-(\d+):/, 1].to_i
        return false if start_line.zero?

        end_line = start_line if end_line < start_line

        path = Pathname(file)
        return false unless path.file?

        lines = path.read.lines

        # A command entry point class under `cmd/`/`dev-cmd/`: keep the class
        # itself (its methods and constants remain removable).
        return true if file.match?(COMMAND_PATH_REGEX) && lines[start_line - 1].to_s.match?(COMMAND_CLASS_REGEX)

        # The definition's own body, e.g. a deprecation call.
        return true if lines[(start_line - 1)...end_line]&.any? { |line| line.match?(DEPRECATION_REGEX) }

        # The contiguous signature and documentation above the definition,
        # stopping at the first blank line (which separates it from any
        # preceding definition).
        index = start_line - 2
        while index >= 0
          text = lines[index].to_s
          break if text.strip.empty?
          return true if text.match?(PERSIST_REGEX)

          index -= 1
        end

        # File-scoped `# deadcode:keep-matching <pattern>` directives matched
        # against this definition's name.
        name = lines[start_line - 1].to_s[/\bdef\s+(?:self\.)?([A-Za-z_]\w*[?!=]?)/, 1]
        if name
          lines.each do |line|
            pattern = line[KEEP_MATCHING_REGEX, 1]
            next if pattern.nil?

            begin
              return true if name.match?(Regexp.new(pattern))
            rescue RegexpError
              next
            end
          end
        end
        false
      end

      sig { params(locations: T::Array[String]).void }
      def remove(locations)
        removed = 0
        skipped = []
        locations.each do |location|
          # Spoom fails on code it can't safely rewrite (e.g. methods wrapped in
          # `begin`/`rescue` or files it cannot parse). Capture its output so a
          # failure doesn't dump a backtrace, and skip that location instead.
          Utils.safe_popen_read("bundle", "exec", "spoom", "deadcode", "remove", location, err: :out)
          removed += 1
        rescue ErrorDuringExecution
          skipped << location
        end

        # Spoom writes a temporary `PATCH` file while computing diffs; clean up
        # any copy left behind by a removal that failed partway through.
        patch = HOMEBREW_LIBRARY_PATH/"PATCH"
        patch.unlink if patch.exist?

        ohai "Removed #{Utils.pluralize("dead code definition", removed, include_count: true)}."
        return if skipped.empty?

        opoo "Skipped #{Utils.pluralize("definition", skipped.count, include_count: true)} Spoom could not remove:"
        skipped.each { |location| puts "  #{location}" }
      end
    end
  end
end
