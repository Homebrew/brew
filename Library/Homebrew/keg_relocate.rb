# typed: strict
# frozen_string_literal: true

class Keg
  PREFIX_PLACEHOLDER = T.let("@@HOMEBREW_PREFIX@@", String)
  CELLAR_PLACEHOLDER = T.let("@@HOMEBREW_CELLAR@@", String)
  REPOSITORY_PLACEHOLDER = T.let("@@HOMEBREW_REPOSITORY@@", String)
  LIBRARY_PLACEHOLDER = T.let("@@HOMEBREW_LIBRARY@@", String)
  PERL_PLACEHOLDER = T.let("@@HOMEBREW_PERL@@", String)
  JAVA_PLACEHOLDER = T.let("@@HOMEBREW_JAVA@@", String)
  NULL_BYTE = T.let("\x00", String)
  NULL_BYTE_STRING = T.let("\\x00", String)

  class Relocation
    RELOCATABLE_PATH_REGEX_PREFIX = T.let(/(?:(?<=-F|-I|-L|-isystem)|(?<![a-zA-Z0-9]))/, Regexp)

    sig { void }
    def initialize
      @replacement_map = T.let({}, T::Hash[Symbol, [T.any(String, Regexp), String]])
    end

    sig { returns(Relocation) }
    def freeze
      @replacement_map.freeze
      super
    end

    sig { params(key: Symbol, old_value: T.any(String, Regexp), new_value: String, path: T::Boolean).void }
    def add_replacement_pair(key, old_value, new_value, path: false)
      old_value = self.class.path_to_regex(old_value) if path
      @replacement_map[key] = [old_value, new_value]
    end

    sig { params(key: Symbol).returns([T.any(String, Regexp), String]) }
    def replacement_pair_for(key)
      @replacement_map.fetch(key)
    end

    sig { params(text: String).returns(T::Boolean) }
    def replace_text!(text)
      replacements = @replacement_map.values.to_h

      sorted_keys = replacements.keys.sort_by do |key|
        key.is_a?(String) ? key.length : 999
      end.reverse

      any_changed = T.let(nil, T.nilable(String))
      sorted_keys.each do |key|
        changed = text.gsub!(key, replacements.fetch(key))
        any_changed ||= changed
      end
      !any_changed.nil?
    end

    sig { params(path: T.any(String, Regexp)).returns(Regexp) }
    def self.path_to_regex(path)
      path = case path
      when String
        Regexp.escape(path)
      when Regexp
        path.source
      end
      Regexp.new(RELOCATABLE_PATH_REGEX_PREFIX.source + path)
    end
  end

  sig { void }
  def fix_dynamic_linkage
    symlink_files.each do |file|
      link = file.readlink
      # Don't fix relative symlinks
      next unless link.absolute?

      link_starts_cellar = link.to_s.start_with?(HOMEBREW_CELLAR.to_s)
      link_starts_prefix = link.to_s.start_with?(HOMEBREW_PREFIX.to_s)
      next if !link_starts_cellar && !link_starts_prefix

      new_src = link.relative_path_from(file.parent)
      file.unlink
      FileUtils.ln_s(new_src, file)
    end
  end

  sig { params(_relocation: Relocation, skip_protodesc_cold: T::Boolean).void }
  def relocate_dynamic_linkage(_relocation, skip_protodesc_cold: false); end

  JAVA_REGEX = %r{#{HOMEBREW_PREFIX}/opt/openjdk(@\d+(\.\d+)*)?/libexec(/openjdk\.jdk/Contents/Home)?}

  sig { returns(T::Hash[Symbol, T::Hash[Symbol, String]]) }
  def new_usr_local_replacement_pairs
    {
      prefix:       {
        old: "/usr/local/opt",
        new: "#{PREFIX_PLACEHOLDER}/opt",
      },
      caskroom:     {
        old: "/usr/local/Caskroom",
        new: "#{PREFIX_PLACEHOLDER}/Caskroom",
      },
      etc_name:     {
        old: "/usr/local/etc/#{name}",
        new: "#{PREFIX_PLACEHOLDER}/etc/#{name}",
      },
      var_homebrew: {
        old: "/usr/local/var/homebrew",
        new: "#{PREFIX_PLACEHOLDER}/var/homebrew",
      },
      var_www:      {
        old: "/usr/local/var/www",
        new: "#{PREFIX_PLACEHOLDER}/var/www",
      },
      var_name:     {
        old: "/usr/local/var/#{name}",
        new: "#{PREFIX_PLACEHOLDER}/var/#{name}",
      },
      var_log_name: {
        old: "/usr/local/var/log/#{name}",
        new: "#{PREFIX_PLACEHOLDER}/var/log/#{name}",
      },
      var_lib_name: {
        old: "/usr/local/var/lib/#{name}",
        new: "#{PREFIX_PLACEHOLDER}/var/lib/#{name}",
      },
      var_run_name: {
        old: "/usr/local/var/run/#{name}",
        new: "#{PREFIX_PLACEHOLDER}/var/run/#{name}",
      },
      var_db_name:  {
        old: "/usr/local/var/db/#{name}",
        new: "#{PREFIX_PLACEHOLDER}/var/db/#{name}",
      },
      share_name:   {
        old: "/usr/local/share/#{name}",
        new: "#{PREFIX_PLACEHOLDER}/share/#{name}",
      },
    }
  end

  sig { params(new_usr_local_relocation: T::Boolean).returns(Relocation) }
  def prepare_relocation_to_placeholders(new_usr_local_relocation: new_usr_local_relocation?)
    relocation = Relocation.new

    # Use selective HOMEBREW_PREFIX replacement when HOMEBREW_PREFIX=/usr/local
    # This avoids overzealous replacement of system paths when a script refers to e.g. /usr/local/bin
    if new_usr_local_relocation
      new_usr_local_replacement_pairs.each do |key, value|
        relocation.add_replacement_pair(key, value.fetch(:old), value.fetch(:new), path: true)
      end
    else
      relocation.add_replacement_pair(:prefix, HOMEBREW_PREFIX.to_s, PREFIX_PLACEHOLDER, path: true)
    end

    relocation.add_replacement_pair(:cellar, HOMEBREW_CELLAR.to_s, CELLAR_PLACEHOLDER, path: true)
    # when HOMEBREW_PREFIX == HOMEBREW_REPOSITORY we should use HOMEBREW_PREFIX for all relocations to avoid
    # being unable to differentiate between them.
    if HOMEBREW_PREFIX != HOMEBREW_REPOSITORY
      relocation.add_replacement_pair(:repository, HOMEBREW_REPOSITORY.to_s, REPOSITORY_PLACEHOLDER, path: true)
    end
    relocation.add_replacement_pair(:library, HOMEBREW_LIBRARY.to_s, LIBRARY_PLACEHOLDER, path: true)
    relocation.add_replacement_pair(:perl,
                                    %r{\A#![ \t]*(?:/usr/bin/perl\d\.\d+|#{HOMEBREW_PREFIX}/opt/perl/bin/perl)( |$)}o,
                                    "#!#{PERL_PLACEHOLDER}\\1")
    relocation.add_replacement_pair(:java, JAVA_REGEX, JAVA_PLACEHOLDER)

    relocation
  end

  sig { returns(T::Array[Pathname]) }
  def replace_locations_with_placeholders
    relocation = prepare_relocation_to_placeholders.freeze
    relocate_dynamic_linkage(relocation, skip_protodesc_cold: true)
    replace_text_in_files(relocation)
  end

  sig { returns(Relocation) }
  def prepare_relocation_to_locations
    relocation = Relocation.new
    relocation.add_replacement_pair(:prefix, PREFIX_PLACEHOLDER, HOMEBREW_PREFIX.to_s)
    relocation.add_replacement_pair(:cellar, CELLAR_PLACEHOLDER, HOMEBREW_CELLAR.to_s)
    relocation.add_replacement_pair(:repository, REPOSITORY_PLACEHOLDER, HOMEBREW_REPOSITORY.to_s)
    relocation.add_replacement_pair(:library, LIBRARY_PLACEHOLDER, HOMEBREW_LIBRARY.to_s)
    relocation.add_replacement_pair(:perl, PERL_PLACEHOLDER, "#{HOMEBREW_PREFIX}/opt/perl/bin/perl")
    if (openjdk = openjdk_dep_name_if_applicable)
      relocation.add_replacement_pair(:java, JAVA_PLACEHOLDER, "#{HOMEBREW_PREFIX}/opt/#{openjdk}/libexec")
    end

    relocation
  end

  sig { params(files: T.nilable(T::Array[Pathname]), skip_linkage: T::Boolean).void }
  def replace_placeholders_with_locations(files, skip_linkage: false)
    relocation = prepare_relocation_to_locations.freeze
    relocate_dynamic_linkage(relocation) unless skip_linkage
    replace_text_in_files(relocation, files:)
  end

  sig { returns(T.nilable(String)) }
  def openjdk_dep_name_if_applicable
    deps = runtime_dependencies
    return if deps.blank?

    dep_names = deps.map { |d| d["full_name"] }
    dep_names.find { |d| d.match? Version.formula_optionally_versioned_regex(:openjdk) }
  end

  sig { params(file: Pathname).returns(T::Boolean) }
  def homebrew_created_file?(file)
    return false unless file.basename.to_s.start_with?("homebrew.")

    %w[.plist .service .timer].include?(file.extname)
  end

  sig { params(relocation: Relocation, files: T.nilable(T::Array[Pathname])).returns(T::Array[Pathname]) }
  def replace_text_in_files(relocation, files: nil)
    files ||= text_files | libtool_files

    changed_files = T.let([], T::Array[Pathname])
    files.map { path.join(it) }.group_by { |f| f.stat.ino }.each_value do |first, *rest|
      first = T.must(first)
      s = first.open("rb", &:read)

      # Use full prefix replacement for Homebrew-created files when using selective relocation
      file_relocation = if new_usr_local_relocation? && homebrew_created_file?(first)
        prepare_relocation_to_placeholders(new_usr_local_relocation: false)
      else
        relocation
      end
      next unless file_relocation.replace_text!(s)

      changed_files += [first, *rest].map { |file| file.relative_path_from(path) }

      begin
        first.atomic_write(s)
      rescue SystemCallError
        first.ensure_writable do
          first.open("wb") { |f| f.write(s) }
        end
      else
        rest.each { |file| FileUtils.ln(first, file, force: true) }
      end
    end
    changed_files
  end

  sig { params(keg: Keg, old_prefix: T.any(String, Pathname), new_prefix: T.any(String, Pathname)).void }
  def relocate_build_prefix(keg, old_prefix, new_prefix)
    each_unique_file_matching(old_prefix) do |file|
      # Skip files which are not binary, as they do not need null padding.
      next unless keg.binary_file?(file)

      # Skip sharballs, which appear to break if patched.
      next if file.text_executable?

      # Split binary by null characters into array and substitute new prefix for old prefix.
      # Null padding is added if the new string is too short.
      file.ensure_writable do
        binary = File.binread file
        odebug "Replacing build prefix in: #{file}"
        binary_strings = binary.split(/#{NULL_BYTE}/o, -1)
        match_indices = binary_strings.each_index.select { |i| binary_strings.fetch(i).include?(old_prefix.to_s) }

        # Only perform substitution on strings which match prefix regex.
        match_indices.each do |i|
          s = binary_strings.fetch(i)
          binary_strings[i] = s.gsub(old_prefix.to_s, new_prefix.to_s)
                               .ljust(s.size, NULL_BYTE)
        end

        # Rejoin strings by null bytes.
        patched_binary = binary_strings.join(NULL_BYTE)
        if patched_binary.size != binary.size
          raise <<~EOS
            Patching failed!  Original and patched binary sizes do not match.
            Original size: #{binary.size}
            Patched size: #{patched_binary.size}
          EOS
        end

        file.atomic_write patched_binary
      end
      codesign_patched_binary(file.to_s)
    end
  end

  sig { params(_options: T::Hash[Symbol, T::Boolean]).returns(T::Array[Symbol]) }
  def detect_cxx_stdlibs(_options = {})
    []
  end

  sig { returns(String) }
  def recursive_fgrep_args
    # for GNU grep; overridden for BSD grep on OS X
    "-lr"
  end

  sig { returns([String, T::Array[String]]) }
  def egrep_args
    grep_bin = "grep"
    grep_args = [
      "--files-with-matches",
      "--perl-regexp",
      "--binary-files=text",
    ]

    [grep_bin, grep_args]
  end

  sig { params(string: T.any(String, Pathname), _block: T.proc.params(arg0: Pathname).void).void }
  def each_unique_file_matching(string, &_block)
    Utils.popen_read("fgrep", recursive_fgrep_args, string, to_s) do |io|
      hardlinks = Set.new

      until io.eof?
        file = Pathname.new(io.readline.chomp)
        # Don't return symbolic links.
        next if file.symlink?

        # To avoid returning hardlinks, only return files with unique inodes.
        # Hardlinks will have the same inode as the file they point to.
        yield file if hardlinks.add? file.stat.ino
      end
    end
  end

  sig { params(file: Pathname).returns(T::Boolean) }
  def binary_file?(file)
    grep_bin, grep_args = egrep_args

    # We need to pass NULL_BYTE_STRING, the literal string "\x00", to grep
    # rather than NULL_BYTE, a literal null byte, because grep will internally
    # convert the literal string "\x00" to a null byte.
    Utils.popen_read(grep_bin, *grep_args, NULL_BYTE_STRING, file).present?
  end

  sig { returns(Pathname) }
  def lib
    path/"lib"
  end

  sig { returns(Pathname) }
  def libexec
    path/"libexec"
  end

  sig { returns(T::Array[Pathname]) }
  def text_files
    text_files = []
    return text_files if !which("file") || !which("xargs")

    # file has known issues with reading files on other locales. Has
    # been fixed upstream for some time, but a sufficiently new enough
    # file with that fix is only available in macOS Sierra.
    # https://bugs.gw.com/view.php?id=292
    # TODO: remove custom logic as we're now not supporting pre-Sierra.
    with_custom_locale("C") do
      files = Set.new path.find.reject { |pn|
        next true if pn.symlink?
        next true if pn.directory?
        next false if pn.basename.to_s == "orig-prefix.txt" # for python virtualenvs
        next true if pn == self/".brew/#{name}.rb"

        require "metafiles"
        next true if Metafiles::EXTENSIONS.include?(pn.extname)

        if pn.text_executable?
          text_files << pn
          next true
        end
        false
      }
      output, _status = Open3.capture2("xargs -0 file --no-dereference --print0",
                                       stdin_data: files.to_a.join("\0"))
      # `file` output sometimes contains data from the file, which may include
      # invalid UTF-8 entities, so tell Ruby this is just a bytestring
      output.force_encoding(Encoding::ASCII_8BIT)
      output.each_line do |line|
        path, info = line.split("\0", 2)
        # `file` sometimes prints more than one line of output per file;
        # subsequent lines do not contain a null-byte separator, so `info`
        # will be `nil` for those lines
        next unless info
        next unless info.include?("text")

        path = Pathname.new(path)
        next unless files.include?(path)

        text_files << path
      end
    end

    text_files
  end

  sig { returns(T::Array[Pathname]) }
  def libtool_files
    libtool_files = []

    path.find do |pn|
      next if pn.symlink? || pn.directory? || Keg::LIBTOOL_EXTENSIONS.exclude?(pn.extname)

      libtool_files << pn
    end
    libtool_files
  end

  sig { returns(T::Array[Pathname]) }
  def symlink_files
    symlink_files = []
    path.find do |pn|
      symlink_files << pn if pn.symlink?
    end

    symlink_files
  end

  sig {
    params(file: Pathname, string: String, ignores: T::Array[Regexp], linked_libraries: T::Array[Pathname],
           formula_and_runtime_deps_names: T.nilable(T::Array[String])).returns(T::Array[[String, String]])
  }
  def self.text_matches_in_file(file, string, ignores, linked_libraries, formula_and_runtime_deps_names)
    text_matches = []
    path_regex = Relocation.path_to_regex(string)
    Utils.popen_read("strings", "-t", "x", "-", file.to_s) do |io|
      until io.eof?
        str = io.readline.chomp
        next if ignores.any? { |i| str.match?(i) }
        next unless str.match? path_regex

        offset, match = str.split(" ", 2)

        # Some binaries contain strings with lists of files
        # e.g. `/usr/local/lib/foo:/usr/local/share/foo:/usr/lib/foo`
        # Each item in the list should be checked separately
        match.split(":").each do |sub_match|
          # Not all items in the list may be matches
          next unless sub_match.match? path_regex
          next if linked_libraries.include? sub_match # Don't bother reporting a string if it was found by otool

          # Do not report matches to files that do not exist.
          next unless File.exist? sub_match

          # Do not report matches to build dependencies.
          if formula_and_runtime_deps_names.present?
            begin
              keg_name = Keg.for(Pathname.new(sub_match)).name
              next unless formula_and_runtime_deps_names.include? keg_name
            rescue NotAKegError
              nil
            end
          end

          text_matches << [match, offset] unless text_matches.any? { |text| text.last == offset }
        end
      end
    end
    text_matches
  end

  sig { params(_file: Pathname, _string: String).returns(T::Array[Pathname]) }
  def self.file_linked_libraries(_file, _string)
    []
  end

  private

  sig { returns(T::Boolean) }
  def new_usr_local_relocation?
    return false if HOMEBREW_PREFIX.to_s != "/usr/local"

    formula = begin
      Formula[name]
    rescue FormulaUnavailableError
      nil
    end
    return true unless formula

    tap = formula.tap
    return true unless tap

    tap.disabled_new_usr_local_relocation_formulae.exclude?(name)
  end
end

require "extend/os/keg_relocate"
