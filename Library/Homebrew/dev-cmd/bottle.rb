# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "fileutils"
require "formula"
require "utils/bottles"
require "tab"
require "sbom"
require "keg"
require "formula_versions"
require "utils/inreplace"
require "erb"
require "utils/gzip"
require "api"
require "extend/hash/deep_merge"
require "metafiles"

module Homebrew
  module DevCmd
    class Bottle < AbstractCommand
      include FileUtils

      BOTTLE_ERB = T.let(<<-EOS.freeze, String)
  bottle do
    <% if [HOMEBREW_BOTTLE_DEFAULT_DOMAIN.to_s,
           "#{HOMEBREW_BOTTLE_DEFAULT_DOMAIN}/bottles"].exclude?(root_url) %>
    root_url "<%= root_url %>"<% if root_url_using.present? %>,
      using: <%= root_url_using %>
    <% end %>
    <% end %>
    <% if rebuild.positive? %>
    rebuild <%= rebuild %>
    <% end %>
    <% sha256_lines.each do |line| %>
    <%= line %>
    <% end %>
  end
      EOS

      MAXIMUM_STRING_MATCHES = 100

      ALLOWABLE_HOMEBREW_REPOSITORY_LINKS = T.let([
        %r{#{Regexp.escape(HOMEBREW_LIBRARY)}/Homebrew/os/(mac|linux)/pkgconfig},
      ].freeze, T::Array[Regexp])

      cmd_args do
        description <<~EOS
          Generate a bottle (binary package) from a formula that was installed with
          `--build-bottle`.
          If the formula specifies a rebuild version, it will be incremented in the
          generated DSL. Passing `--keep-old` will attempt to keep it at its original
          value, while `--no-rebuild` will remove it.
        EOS
        switch "--skip-relocation",
               description: "Do not check if the bottle can be marked as relocatable."
        switch "--force-core-tap",
               description: "Build a bottle even if <formula> is not in `homebrew/core` or any installed taps."
        switch "--no-rebuild",
               description: "If the formula specifies a rebuild version, remove it from the generated DSL."
        switch "--keep-old",
               description: "If the formula specifies a rebuild version, attempt to preserve its value in the " \
                            "generated DSL."
        switch "--json",
               description: "Write bottle information to a JSON file, which can be used as the value for " \
                            "`--merge`."
        switch "--merge",
               description: "Generate an updated bottle block for a formula and optionally merge it into the " \
                            "formula file. Instead of a formula name, requires the path to a JSON file generated " \
                            "with `brew bottle --json` <formula>."
        switch "--write",
               depends_on:  "--merge",
               description: "Write changes to the formula file. A new commit will be generated unless " \
                            "`--no-commit` is passed."
        switch "--no-commit",
               depends_on:  "--write",
               description: "When passed with `--write`, a new commit will not generated after writing changes " \
                            "to the formula file."
        switch "--only-json-tab",
               depends_on:  "--json",
               description: "When passed with `--json`, the tab will be written to the JSON file but not the bottle."
        switch "--no-all-checks",
               depends_on:  "--merge",
               description: "Don't try to create an `all` bottle or stop a no-change upload."
        flag   "--committer=",
               description: "Specify a committer name and email in `git`'s standard author format."
        flag   "--root-url=",
               description: "Use the specified <URL> as the root of the bottle's URL instead of Homebrew's default."
        flag   "--root-url-using=",
               description: "Use the specified download strategy class for downloading the bottle's URL instead of " \
                            "Homebrew's default."

        conflicts "--no-rebuild", "--keep-old"

        named_args [:installed_formula, :file], min: 1, without_api: true
      end

      sig { override.void }
      def run
        if args.merge?
          Homebrew.install_bundler_gems!(groups: ["ast"])
          return merge
        end

        Homebrew.install_bundler_gems!(groups: ["bottle"])

        gnu_tar_formula_ensure_installed_if_needed! if args.only_json_tab?

        args.named.to_resolved_formulae(uniq: false).each do |formula|
          bottle_formula formula
        end
      end

      sig {
        params(tag: Symbol, digest: T.any(Checksum, String), cellar: T.nilable(T.any(String, Symbol)),
               tag_column: Integer, digest_column: Integer).returns(String)
      }
      def generate_sha256_line(tag, digest, cellar, tag_column, digest_column)
        line = "sha256 "
        tag_column += line.length
        digest_column += line.length
        if cellar.is_a?(Symbol)
          line += "cellar: :#{cellar},"
        elsif cellar_parameter_needed?(cellar)
          line += %Q(cellar: "#{cellar}",)
        end
        line += " " * (tag_column - line.length)
        line += "#{tag}:"
        line += " " * (digest_column - line.length)
        %Q(#{line}"#{digest}")
      end

      sig { params(bottle: BottleSpecification, root_url_using: T.nilable(String)).returns(String) }
      def bottle_output(bottle, root_url_using)
        cellars = bottle.checksums.filter_map do |checksum|
          cellar = checksum["cellar"]
          next unless cellar_parameter_needed? cellar

          case cellar
          when String
            %Q("#{cellar}")
          when Symbol
            ":#{cellar}"
          end
        end
        tag_column = cellars.empty? ? 0 : "cellar: #{cellars.max_by(&:length)}, ".length

        tags = bottle.checksums.map { |checksum| checksum["tag"] }
        # Start where the tag ends, add the max length of the tag, add two for the `: `
        digest_column = tag_column + tags.max_by(&:length).length + 2

        sha256_lines = bottle.checksums.map do |checksum|
          generate_sha256_line(checksum["tag"], checksum["digest"], checksum["cellar"], tag_column, digest_column)
        end
        erb_binding = bottle.instance_eval { binding }
        erb_binding.local_variable_set(:sha256_lines, sha256_lines)
        erb_binding.local_variable_set(:root_url_using, root_url_using)
        erb = ERB.new BOTTLE_ERB
        erb.result(erb_binding).gsub(/^\s*$\n/, "")
      end

      sig { params(filenames: T::Array[String]).returns(T::Array[T::Hash[String, T.untyped]]) }
      def parse_json_files(filenames)
        filenames.map do |filename|
          JSON.parse(File.read(filename))
        end
      end

      sig { params(json_files: T::Array[T::Hash[String, T.untyped]]).returns(T::Hash[String, T.untyped]) }
      def merge_json_files(json_files)
        json_files.reduce({}) do |hash, json_file|
          json_file.each_value do |json_hash|
            json_bottle = json_hash["bottle"]
            cellar = json_bottle.delete("cellar")
            json_bottle["tags"].each_value do |json_platform|
              json_platform["cellar"] ||= cellar
            end
          end
          hash.deep_merge(json_file)
        end
      end

      sig {
        params(old_keys: T::Array[String], old_bottle_spec: BottleSpecification,
               new_bottle_hash: T::Hash[String, T.untyped]).returns(T::Array[T::Array[String]])
      }
      def merge_bottle_spec(old_keys, old_bottle_spec, new_bottle_hash)
        mismatches = []
        checksums = []

        new_values = {
          root_url: new_bottle_hash["root_url"],
          rebuild:  new_bottle_hash["rebuild"],
        }

        skip_keys = [:sha256, :cellar]
        old_keys.each do |key|
          next if skip_keys.include?(key)

          old_value = old_bottle_spec.send(key).to_s
          new_value = new_values[key].to_s

          next if old_value.present? && new_value == old_value

          mismatches << "#{key}: old: #{old_value.inspect}, new: #{new_value.inspect}"
        end

        return [mismatches, checksums] if old_keys.exclude? :sha256

        old_bottle_spec.collector.each_tag do |tag|
          old_tag_spec = old_bottle_spec.collector.specification_for(tag)
          old_hexdigest = old_tag_spec.checksum.hexdigest
          old_cellar = old_tag_spec.cellar
          new_value = new_bottle_hash.dig("tags", tag.to_s)
          if new_value.present? && new_value["sha256"] != old_hexdigest
            mismatches << "sha256 #{tag}: old: #{old_hexdigest.inspect}, new: #{new_value["sha256"].inspect}"
          elsif new_value.present? && new_value["cellar"] != old_cellar.to_s
            mismatches << "cellar #{tag}: old: #{old_cellar.to_s.inspect}, new: #{new_value["cellar"].inspect}"
          else
            checksums << { cellar: old_cellar, tag.to_sym => old_hexdigest }
          end
        end

        [mismatches, checksums]
      end

      private

      sig {
        params(string: String, keg: Keg, ignores: T::Array[String],
               formula_and_runtime_deps_names: T.nilable(T::Array[String])).returns(T::Boolean)
      }
      def keg_contain?(string, keg, ignores, formula_and_runtime_deps_names = nil)
        @put_string_exists_header, @put_filenames = nil

        print_filename = lambda do |str, filename|
          unless @put_string_exists_header
            opoo "String '#{str}' still exists in these files:"
            @put_string_exists_header = T.let(true, T.nilable(T::Boolean))
          end

          @put_filenames ||= T.let([], T.nilable(T::Array[T.any(String, Pathname)]))

          return false if @put_filenames.include?(filename)

          puts Formatter.error(filename.to_s)
          @put_filenames << filename
        end

        result = T.let(false, T::Boolean)

        keg.each_unique_file_matching(string) do |file|
          next if Metafiles::EXTENSIONS.include?(file.extname) # Skip document files.

          linked_libraries = Keg.file_linked_libraries(file, string)
          result ||= !linked_libraries.empty?

          if args.verbose?
            print_filename.call(string, file) unless linked_libraries.empty?
            linked_libraries.each do |lib|
              puts " #{Tty.bold}-->#{Tty.reset} links to #{lib}"
            end
          end

          text_matches = Keg.text_matches_in_file(file, string, ignores, linked_libraries,
                                                  formula_and_runtime_deps_names)
          result = true if text_matches.any?

          next if !args.verbose? || text_matches.empty?

          print_filename.call(string, file)
          text_matches.first(MAXIMUM_STRING_MATCHES).each do |match, offset|
            puts " #{Tty.bold}-->#{Tty.reset} match '#{match}' at offset #{Tty.bold}0x#{offset}#{Tty.reset}"
          end

          if text_matches.size > MAXIMUM_STRING_MATCHES
            puts "Only the first #{MAXIMUM_STRING_MATCHES} matches were output."
          end
        end

        keg_contain_absolute_symlink_starting_with?(string, keg) || result
      end

      sig { params(string: String, keg: Keg).returns(T::Boolean) }
      def keg_contain_absolute_symlink_starting_with?(string, keg)
        absolute_symlinks_start_with_string = []
        keg.find do |pn|
          next if !pn.symlink? || !(link = pn.readlink).absolute?

          absolute_symlinks_start_with_string << pn if link.to_s.start_with?(string)
        end

        if args.verbose? && absolute_symlinks_start_with_string.present?
          opoo "Absolute symlink starting with #{string}:"
          absolute_symlinks_start_with_string.each do |pn|
            puts "  #{pn} -> #{pn.resolved_path}"
          end
        end

        !absolute_symlinks_start_with_string.empty?
      end

      sig { params(cellar: T.nilable(T.any(String, Symbol))).returns(T::Boolean) }
      def cellar_parameter_needed?(cellar)
        default_cellars = [
          Homebrew::DEFAULT_MACOS_CELLAR,
          Homebrew::DEFAULT_MACOS_ARM_CELLAR,
          Homebrew::DEFAULT_LINUX_CELLAR,
        ]
        cellar.present? && default_cellars.exclude?(cellar)
      end

      sig { returns(T.nilable(T::Boolean)) }
      def sudo_purge
        return unless ENV["HOMEBREW_BOTTLE_SUDO_PURGE"]

        system "/usr/bin/sudo", "--non-interactive", "/usr/sbin/purge"
      end

      sig { returns(T::Array[String]) }
      def tar_args
        [].freeze
      end

      sig { params(gnu_tar_formula: Formula).returns(String) }
      def gnu_tar(gnu_tar_formula)
        "#{gnu_tar_formula.opt_bin}/tar"
      end

      sig { params(mtime: String).returns(T::Array[String]) }
      def reproducible_gnutar_args(mtime)
        # Ensure gnu tar is set up for reproducibility.
        # https://reproducible-builds.org/docs/archives/
        [
          # File modification times
          "--mtime=#{mtime}",
          # File ordering
          "--sort=name",
          # Users, groups and numeric ids
          "--owner=0", "--group=0", "--numeric-owner",
          # PAX headers
          "--format=pax",
          # Set exthdr names to exclude PID (for GNU tar <1.33). Also don't store atime and ctime.
          "--pax-option=globexthdr.name=/GlobalHead.%n,exthdr.name=%d/PaxHeaders/%f,delete=atime,delete=ctime"
        ].freeze
      end

      sig { returns(T.nilable(Formula)) }
      def gnu_tar_formula_ensure_installed_if_needed!
        gnu_tar_formula = begin
          Formula["gnu-tar"]
        rescue FormulaUnavailableError
          nil
        end
        return if gnu_tar_formula.blank?

        ensure_formula_installed!(gnu_tar_formula, reason: "bottling")

        gnu_tar_formula
      end

      sig { params(mtime: String, default_tar: T::Boolean).returns([String, T::Array[String]]) }
      def setup_tar_and_args!(mtime, default_tar: false)
        # Without --only-json-tab bottles are never reproducible
        default_tar_args = ["tar", tar_args].freeze
        return default_tar_args if !args.only_json_tab? || default_tar

        # Use gnu-tar as it can be set up for reproducibility better than libarchive
        # and to be consistent between macOS and Linux.
        gnu_tar_formula = gnu_tar_formula_ensure_installed_if_needed!
        return default_tar_args if gnu_tar_formula.blank?

        [gnu_tar(gnu_tar_formula), reproducible_gnutar_args(mtime)].freeze
      end

      sig { params(formula: T.untyped).returns(T::Array[T.untyped]) }
      def formula_ignores(formula)
        ignores = []
        cellar_regex = Regexp.escape(HOMEBREW_CELLAR)
        prefix_regex = Regexp.escape(HOMEBREW_PREFIX)

        # Ignore matches to go keg, because all go binaries are statically linked.
        any_go_deps = formula.deps.any? do |dep|
          Version.formula_optionally_versioned_regex(:go).match?(dep.name)
        end
        if any_go_deps
          go_regex = Version.formula_optionally_versioned_regex(:go, full: false)
          ignores << %r{#{cellar_regex}/#{go_regex}/[\d.]+/libexec}
        end

        # TODO: Refactor and move to extend/os
        # rubocop:disable Homebrew/MoveToExtendOS
        ignores << case formula.name
        # On Linux, GCC installation can be moved so long as the whole directory tree is moved together:
        # https://gcc-help.gcc.gnu.narkive.com/GnwuCA7l/moving-gcc-from-the-installation-path-is-it-allowed.
        when Version.formula_optionally_versioned_regex(:gcc)
          Regexp.union(%r{#{cellar_regex}/gcc}, %r{#{prefix_regex}/opt/gcc}) if OS.linux?
        # binutils is relocatable for the same reason: https://github.com/Homebrew/brew/pull/11899#issuecomment-906804451.
        when Version.formula_optionally_versioned_regex(:binutils)
          %r{#{cellar_regex}/binutils} if OS.linux?
        end
        # rubocop:enable Homebrew/MoveToExtendOS

        ignores.compact
      end

      sig { params(formula: Formula).void }
      def bottle_formula(formula)
        local_bottle_json = args.json? && formula.local_bottle_path.present?

        unless local_bottle_json
          unless formula.latest_version_installed?
            return ofail "Formula not installed or up-to-date: #{formula.full_name}"
          end
          unless Utils::Bottles.built_as? formula
            return ofail "Formula was not installed with `--build-bottle`: #{formula.full_name}"
          end
        end

        tap = formula.tap
        if tap.nil?
          return ofail "Formula not from core or any installed taps: #{formula.full_name}" unless args.force_core_tap?

          tap = CoreTap.instance
        end
        raise TapUnavailableError, tap.name unless tap.installed?

        return ofail "Formula has no stable version: #{formula.full_name}" unless formula.stable

        bottle_tag, rebuild = if local_bottle_json
          _, tag_string, rebuild_string = Utils::Bottles.extname_tag_rebuild(formula.local_bottle_path.to_s)
          [tag_string.to_sym, rebuild_string.to_i]
        end

        bottle_tag = if bottle_tag
          Utils::Bottles::Tag.from_symbol(bottle_tag)
        else
          Utils::Bottles.tag
        end

        rebuild ||= if args.no_rebuild? || !tap
          0
        elsif args.keep_old?
          formula.bottle_specification.rebuild
        else
          ohai "Determining #{formula.full_name} bottle rebuild..."
          FormulaVersions.new(formula).formula_at_revision("origin/HEAD") do |upstream_formula|
            if formula.pkg_version == upstream_formula.pkg_version
              upstream_formula.bottle_specification.rebuild + 1
            else
              0
            end
          end || 0
        end

        filename = ::Bottle::Filename.create(formula, bottle_tag, rebuild)
        local_filename = filename.to_s
        bottle_path = Pathname.pwd/local_filename

        tab = nil
        keg = nil

        tap_path = tap.path
        tap_git_revision = tap.git_head
        tap_git_remote = tap.remote

        root_url = args.root_url

        relocatable = T.let(false, T::Boolean)
        skip_relocation = T.let(false, T::Boolean)

        prefix = HOMEBREW_PREFIX.to_s
        cellar = HOMEBREW_CELLAR.to_s

        if local_bottle_json
          bottle_path = formula.local_bottle_path
          return if bottle_path.blank?

          local_filename = bottle_path.basename.to_s

          tab_path = Utils::Bottles.receipt_path(bottle_path)
          raise "This bottle does not contain the file INSTALL_RECEIPT.json: #{bottle_path}" unless tab_path

          tab_json = Utils::Bottles.file_from_bottle(bottle_path, tab_path)
          tab = Tab.from_file_content(tab_json, tab_path)

          tag_spec = Formula[formula.name].bottle_specification
                                          .tag_specification_for(bottle_tag, no_older_versions: true)
          relocatable = [:any, :any_skip_relocation].include?(tag_spec.cellar)
          skip_relocation = tag_spec.cellar == :any_skip_relocation

          prefix = bottle_tag.default_prefix
          cellar = bottle_tag.default_cellar
        else
          tar_filename = filename.to_s.sub(/.gz$/, "")
          tar_path = Pathname.pwd/tar_filename
          return if tar_path.blank?

          keg = Keg.new(formula.prefix)
        end

        ohai "Bottling #{local_filename}..."

        formula_and_runtime_deps_names = [formula.name] + formula.runtime_dependencies.map(&:name)

        # this will be nil when using a local bottle
        keg&.lock do
          original_tab = nil
          changed_files = nil

          begin
            keg.delete_pyc_files!

            changed_files = keg.replace_locations_with_placeholders unless args.skip_relocation?

            Formula.clear_cache
            Keg.clear_cache
            Tab.clear_cache
            Dependency.clear_cache
            Requirement.clear_cache

            tab = keg.tab
            original_tab = tab.dup
            tab.poured_from_bottle = false
            tab.time = nil
            tab.changed_files = changed_files.dup
            if args.only_json_tab?
              tab.changed_files.delete(Pathname.new(AbstractTab::FILENAME))
              tab.tabfile.unlink
            else
              tab.write
            end

            sbom = SBOM.create(formula, tab)
            sbom.write(bottling: true)

            keg.consistent_reproducible_symlink_permissions!

            cd cellar do
              sudo_purge
              # Tar then gzip for reproducible bottles.
              tar_mtime = tab.source_modified_time.strftime("%Y-%m-%d %H:%M:%S")
              tar, tar_args = setup_tar_and_args!(tar_mtime, default_tar: formula.name == "gnu-tar")
              safe_system tar, "--create", "--numeric-owner",
                          *tar_args,
                          "--file", tar_path, "#{formula.name}/#{formula.pkg_version}"
              sudo_purge
              # Set filename as it affects the tarball checksum.
              relocatable_tar_path = "#{formula}-bottle.tar"
              mv T.must(tar_path), relocatable_tar_path
              # Use gzip, faster to compress than bzip2, faster to uncompress than bzip2
              # or an uncompressed tarball (and more bandwidth friendly).
              Utils::Gzip.compress_with_options(relocatable_tar_path,
                                                mtime:     tab.source_modified_time,
                                                orig_name: relocatable_tar_path,
                                                output:    bottle_path)
              sudo_purge
            end

            ohai "Detecting if #{local_filename} is relocatable..." if bottle_path.size > 1 * 1024 * 1024

            prefix_check = if prefix == HOMEBREW_DEFAULT_PREFIX
              File.join(prefix, "opt")
            else
              prefix
            end

            # Ignore matches to source code, which is not required at run time.
            # These matches may be caused by debugging symbols.
            ignores = [%r{/include/|\.(c|cc|cpp|h|hpp)$}]

            # Add additional workarounds to ignore
            ignores += formula_ignores(formula)

            repository_reference = if HOMEBREW_PREFIX == HOMEBREW_REPOSITORY
              HOMEBREW_LIBRARY
            else
              HOMEBREW_REPOSITORY
            end.to_s
            if keg_contain?(repository_reference, keg, ignores + ALLOWABLE_HOMEBREW_REPOSITORY_LINKS)
              odie "Bottle contains non-relocatable reference to #{repository_reference}!"
            end

            relocatable = true
            if args.skip_relocation?
              skip_relocation = true
            else
              relocatable = false if keg_contain?(prefix_check, keg, ignores, formula_and_runtime_deps_names)
              relocatable = false if keg_contain?(cellar, keg, ignores, formula_and_runtime_deps_names)
              relocatable = false if keg_contain?(HOMEBREW_LIBRARY.to_s, keg, ignores, formula_and_runtime_deps_names)
              if prefix != prefix_check
                relocatable = false if keg_contain_absolute_symlink_starting_with?(prefix, keg)
                relocatable = false if keg_contain?("#{prefix}/etc", keg, ignores)
                relocatable = false if keg_contain?("#{prefix}/var", keg, ignores)
                relocatable = false if keg_contain?("#{prefix}/share/vim", keg, ignores)
              end
              skip_relocation = relocatable && !keg.require_relocation?
            end
            puts if !relocatable && args.verbose?
          rescue Interrupt
            ignore_interrupts { bottle_path.unlink if bottle_path.exist? }
            raise
          ensure
            ignore_interrupts do
              original_tab&.write
              keg.replace_placeholders_with_locations changed_files unless args.skip_relocation?
            end
          end
        end

        bottle = BottleSpecification.new
        bottle.tap = tap
        bottle.root_url(root_url) if root_url
        bottle_cellar = if relocatable
          if skip_relocation
            :any_skip_relocation
          else
            :any
          end
        else
          cellar
        end
        bottle.rebuild rebuild
        sha256 = bottle_path.sha256
        bottle.sha256 cellar: bottle_cellar, bottle_tag.to_sym => sha256

        old_spec = formula.bottle_specification
        if args.keep_old? && !old_spec.checksums.empty?
          mismatches = [:root_url, :rebuild].reject do |key|
            old_spec.send(key) == bottle.send(key)
          end
          unless mismatches.empty?
            bottle_path.unlink if bottle_path.exist?

            mismatches.map! do |key|
              old_value = old_spec.send(key).inspect
              value = bottle.send(key).inspect
              "#{key}: old: #{old_value}, new: #{value}"
            end

            odie <<~EOS
              `--keep-old` was passed but there are changes in:
              #{mismatches.join("\n")}
            EOS
          end
        end

        output = bottle_output(bottle, args.root_url_using)

        puts "./#{local_filename}"
        puts output

        return unless args.json?

        if keg
          keg_prefix = "#{keg}/"
          path_exec_files = [keg/"bin", keg/"sbin"].select(&:exist?)
                                                   .flat_map(&:children)
                                                   .select(&:executable?)
                                                   .map { |path| path.to_s.delete_prefix(keg_prefix) }
          all_files = keg.find
                         .select(&:file?)
                         .map { |path| path.to_s.delete_prefix(keg_prefix) }
          installed_size = keg.disk_usage
        end

        json = {
          formula.full_name => {
            "formula" => {
              "name"             => formula.name,
              "pkg_version"      => formula.pkg_version.to_s,
              "path"             => formula.path.to_s.delete_prefix("#{HOMEBREW_REPOSITORY}/"),
              "tap_git_path"     => formula.path.to_s.delete_prefix("#{tap_path}/"),
              "tap_git_revision" => tap_git_revision,
              "tap_git_remote"   => tap_git_remote,
              # descriptions can contain emoji. sigh.
              "desc"             => formula.desc.to_s.encode(
                Encoding.find("ASCII"),
                invalid: :replace, undef: :replace, replace: "",
              ).strip,
              "license"          => SPDX.license_expression_to_string(formula.license),
              "homepage"         => formula.homepage,
            },
            "bottle"  => {
              "root_url" => bottle.root_url,
              "cellar"   => bottle_cellar.to_s,
              "rebuild"  => bottle.rebuild,
              # date is used for org.opencontainers.image.created which is an RFC 3339 date-time.
              # Time#iso8601 produces an XML Schema date-time that meets RFC 3339 ABNF.
              "date"     => Pathname(filename.to_s).mtime.utc.iso8601,
              "tags"     => {
                bottle_tag.to_s => {
                  "filename"        => filename.url_encode,
                  "local_filename"  => filename.to_s,
                  "sha256"          => sha256,
                  "tab"             => tab.to_bottle_hash,
                  "path_exec_files" => path_exec_files,
                  "all_files"       => all_files,
                  "installed_size"  => installed_size,
                },
              },
            },
          },
        }

        puts "Writing #{filename.json}" if args.verbose?
        json_path = Pathname(filename.json)
        json_path.unlink if json_path.exist?
        json_path.write(JSON.pretty_generate(json))
      end

      sig { returns(T::Hash[String, T.untyped]) }
      def merge
        bottles_hash = merge_json_files(parse_json_files(args.named))

        any_cellars = ["any", "any_skip_relocation"]
        bottles_hash.each do |formula_name, bottle_hash|
          ohai formula_name

          bottle = BottleSpecification.new
          bottle.root_url bottle_hash["bottle"]["root_url"]
          bottle.rebuild bottle_hash["bottle"]["rebuild"]

          path = HOMEBREW_REPOSITORY/bottle_hash["formula"]["path"]
          formula = Formulary.factory(path)

          old_bottle_spec = formula.bottle_specification
          old_pkg_version = formula.pkg_version
          FormulaVersions.new(formula).formula_at_revision("origin/HEAD") do |upstream_formula|
            old_pkg_version = upstream_formula.pkg_version
          end

          old_bottle_spec_matches = old_bottle_spec &&
                                    bottle_hash["formula"]["pkg_version"] == old_pkg_version.to_s &&
                                    bottle.root_url == old_bottle_spec.root_url &&
                                    old_bottle_spec.collector.tags.present?

          # if all the cellars and checksums are the same: we can create an
          # `all: $SHA256` bottle.
          tag_hashes = bottle_hash["bottle"]["tags"].values
          all_bottle = !args.no_all_checks? &&
                       (!old_bottle_spec_matches || bottle.rebuild != old_bottle_spec.rebuild) &&
                       tag_hashes.count > 1 &&
                       tag_hashes.uniq { |tag_hash| "#{tag_hash["cellar"]}-#{tag_hash["sha256"]}" }.count == 1

          old_all_bottle = old_bottle_spec.tag?(Utils::Bottles.tag(:all))
          if !all_bottle && old_all_bottle && !args.no_all_checks?
            odie <<~ERROR
              #{formula} should have an `:all` bottle but one cannot be created:
              #{JSON.pretty_generate(tag_hashes)}
            ERROR
          end

          bottle_hash["bottle"]["tags"].each do |tag, tag_hash|
            cellar = tag_hash["cellar"]
            cellar = cellar.to_sym if any_cellars.include?(cellar)

            tag_sym = if all_bottle
              :all
            else
              tag.to_sym
            end

            sha256_hash = { cellar:, tag_sym => tag_hash["sha256"] }
            bottle.sha256 sha256_hash

            break if all_bottle
          end

          unless args.write?
            puts bottle_output(bottle, args.root_url_using)
            next
          end

          no_bottle_changes = if !args.no_all_checks? && old_bottle_spec_matches &&
                                 bottle.rebuild != old_bottle_spec.rebuild
            bottle.collector.tags.all? do |tag|
              tag_spec = bottle.collector.specification_for(tag)
              next false if tag_spec.blank?

              old_tag_spec = old_bottle_spec.collector.specification_for(tag)
              next false if old_tag_spec.blank?

              next false if tag_spec.cellar != old_tag_spec.cellar

              tag_spec.checksum.hexdigest == old_tag_spec.checksum.hexdigest
            end
          end

          all_bottle_hash = T.let(nil, T.nilable(T::Hash[String, T.untyped]))
          bottle_hash["bottle"]["tags"].each do |tag, tag_hash|
            filename = ::Bottle::Filename.new(
              formula_name,
              PkgVersion.parse(bottle_hash["formula"]["pkg_version"]),
              Utils::Bottles::Tag.from_symbol(tag.to_sym),
              bottle_hash["bottle"]["rebuild"],
            )

            if all_bottle && all_bottle_hash.nil?
              all_bottle_tag_hash = tag_hash.dup

              all_filename = ::Bottle::Filename.new(
                formula_name,
                PkgVersion.parse(bottle_hash["formula"]["pkg_version"]),
                Utils::Bottles::Tag.from_symbol(:all),
                bottle_hash["bottle"]["rebuild"],
              )

              all_bottle_tag_hash["filename"] = all_filename.url_encode
              all_bottle_tag_hash["local_filename"] = all_filename.to_s
              cellar = all_bottle_tag_hash.delete("cellar")

              all_bottle_formula_hash = bottle_hash.dup
              all_bottle_formula_hash["bottle"]["cellar"] = cellar
              all_bottle_formula_hash["bottle"]["tags"] = { all: all_bottle_tag_hash }

              all_bottle_hash = { formula_name => all_bottle_formula_hash }

              puts "Copying #{filename} to #{all_filename}" if args.verbose?
              FileUtils.cp filename.to_s, all_filename.to_s

              puts "Writing #{all_filename.json}" if args.verbose?
              all_local_json_path = Pathname(all_filename.json)
              all_local_json_path.unlink if all_local_json_path.exist?
              all_local_json_path.write(JSON.pretty_generate(all_bottle_hash))
            end

            if all_bottle || no_bottle_changes
              puts "Removing #{filename} and #{filename.json}" if args.verbose?
              FileUtils.rm_f [filename.to_s, filename.json]
            end
          end

          next if no_bottle_changes

          require "utils/ast"
          formula_ast = Utils::AST::FormulaAST.new(path.read)
          checksums = old_checksums(formula, formula_ast, bottle_hash)
          update_or_add = checksums.nil? ? "add" : "update"

          checksums&.each { |checksum| bottle.sha256(checksum) }
          output = bottle_output(bottle, args.root_url_using)
          puts output

          case update_or_add
          when "update"
            formula_ast.replace_bottle_block(output)
          when "add"
            formula_ast.add_bottle_block(output)
          end
          path.atomic_write(formula_ast.process)

          next if args.no_commit?

          Utils::Git.set_name_email!(committer: args.committer.blank?)
          Utils::Git.setup_gpg!

          if (committer = args.committer)
            committer = Utils.parse_author!(committer)
            ENV["GIT_COMMITTER_NAME"] = committer[:name]
            ENV["GIT_COMMITTER_EMAIL"] = committer[:email]
          end

          short_name = formula_name.split("/", -1).last
          pkg_version = bottle_hash["formula"]["pkg_version"]

          path.parent.cd do
            safe_system "git", "commit", "--no-edit", "--verbose",
                        "--message=#{short_name}: #{update_or_add} #{pkg_version} bottle.",
                        "--", path
          end
        end
      end

      sig {
        params(formula: Formula, formula_ast: Utils::AST::FormulaAST,
               bottle_hash: T::Hash[String, T.untyped]).returns(T.nilable(T::Array[String]))
      }
      def old_checksums(formula, formula_ast, bottle_hash)
        bottle_node = T.cast(formula_ast.bottle_block, T.nilable(RuboCop::AST::BlockNode))
        return if bottle_node.nil?
        return [] unless args.keep_old?

        old_keys = T.cast(Utils::AST.body_children(bottle_node.body), T::Array[RuboCop::AST::SendNode])
                    .map(&:method_name)
        old_bottle_spec = formula.bottle_specification
        mismatches, checksums = merge_bottle_spec(old_keys, old_bottle_spec, bottle_hash["bottle"])
        if mismatches.present?
          odie <<~EOS
            `--keep-old` was passed but there are changes in:
            #{mismatches.join("\n")}
          EOS
        end
        checksums
      end
    end
  end
end

require "extend/os/dev-cmd/bottle"
