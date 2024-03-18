# typed: true
# frozen_string_literal: true

class Keg
  PREFIX_PLACEHOLDER = "@@HOMEBREW_PREFIX@@"
  CELLAR_PLACEHOLDER = "@@HOMEBREW_CELLAR@@"
  REPOSITORY_PLACEHOLDER = "@@HOMEBREW_REPOSITORY@@"
  LIBRARY_PLACEHOLDER = "@@HOMEBREW_LIBRARY@@"
  PERL_PLACEHOLDER = "@@HOMEBREW_PERL@@"
  JAVA_PLACEHOLDER = "@@HOMEBREW_JAVA@@"
  NULL_BYTE = "\x00"
  NULL_BYTE_STRING = "\\x00"

  class Relocation
    RELOCATABLE_PATH_REGEX_PREFIX = /(?:(?<=-F|-I|-L|-isystem)|(?<![a-zA-Z0-9]))/

    def initialize
      @replacement_map = {}
    end

    def freeze
      @replacement_map.freeze
      super
    end

    sig { params(key: Symbol, old_value: T.any(String, Regexp), new_value: String, path: T::Boolean).void }
    def add_replacement_pair(key, old_value, new_value, path: false)
      old_value = self.class.path_to_regex(old_value) if path
      @replacement_map[key] = [old_value, new_value]
    end

    sig { params(key: Symbol).returns(T::Array[T.any(String, Regexp)]) }
    def replacement_pair_for(key)
      @replacement_map.fetch(key)
    end

    sig { params(text: String).returns(T::Boolean) }
    def replace_text(text)
      replacements = @replacement_map.values.to_h

      sorted_keys = replacements.keys.sort_by do |key|
        key.is_a?(String) ? key.length : 999
      end.reverse

      any_changed = T.let(nil, T.nilable(String))
      sorted_keys.each do |key|
        changed = text.gsub!(key, replacements[key])
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
  alias generic_fix_dynamic_linkage fix_dynamic_linkage

  def relocate_dynamic_linkage(_relocation)
    []
  end

  JAVA_REGEX = %r{#{HOMEBREW_PREFIX}/opt/openjdk(@\d+(\.\d+)*)?/libexec(/openjdk\.jdk/Contents/Home)?}

  def prepare_relocation_to_placeholders
    relocation = Relocation.new
    relocation.add_replacement_pair(:prefix, HOMEBREW_PREFIX.to_s, PREFIX_PLACEHOLDER, path: true)
    relocation.add_replacement_pair(:cellar, HOMEBREW_CELLAR.to_s, CELLAR_PLACEHOLDER, path: true)
    # when HOMEBREW_PREFIX == HOMEBREW_REPOSITORY we should use HOMEBREW_PREFIX for all relocations to avoid
    # being unable to differentiate between them.
    if HOMEBREW_PREFIX != HOMEBREW_REPOSITORY
      relocation.add_replacement_pair(:repository, HOMEBREW_REPOSITORY.to_s, REPOSITORY_PLACEHOLDER, path: true)
    end
    relocation.add_replacement_pair(:library, HOMEBREW_LIBRARY.to_s, LIBRARY_PLACEHOLDER, path: true)
    relocation.add_replacement_pair(:perl,
                                    %r{\A#!(?:/usr/bin/perl\d\.\d+|#{HOMEBREW_PREFIX}/opt/perl/bin/perl)( |$)}o,
                                    "#!#{PERL_PLACEHOLDER}\\1")
    relocation.add_replacement_pair(:java, JAVA_REGEX, JAVA_PLACEHOLDER)

    relocation
  end
  alias generic_prepare_relocation_to_placeholders prepare_relocation_to_placeholders

  def replace_locations_with_placeholders
    relocation = prepare_relocation_to_placeholders.freeze
    relocate_dynamic_linkage(relocation)
    replace_text_in_files(relocation)
  end

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
  alias generic_prepare_relocation_to_locations prepare_relocation_to_locations

  def replace_placeholders_with_locations(files, skip_linkage: false)
    relocation = prepare_relocation_to_locations.freeze
    relocate_dynamic_linkage(relocation) unless skip_linkage
    replace_text_in_files(relocation, files:)
  end

  def openjdk_dep_name_if_applicable
    deps = runtime_dependencies
    return if deps.blank?

    dep_names = deps.map { |d| d["full_name"] }
    dep_names.find { |d| d.match? Version.formula_optionally_versioned_regex(:openjdk) }
  end

  def replace_text_in_files(relocation, files: nil)
    files ||= text_files | libtool_files

    changed_files = T.let([], Array)
    files.map { path.join(_1) }.group_by { |f| f.stat.ino }.each_value do |first, *rest|
      s = first.open("rb", &:read)

      next unless relocation.replace_text(s)

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
        match_indices = binary_strings.each_index.select { |i| binary_strings.fetch(i).include?(old_prefix) }

        # Only perform substitution on strings which match prefix regex.
        match_indices.each do |i|
          s = binary_strings.fetch(i)
          binary_strings[i] = s.gsub(old_prefix, new_prefix)
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
      codesign_patched_binary(file)
    end
  end

  def detect_cxx_stdlibs(_options = {})
    []
  end

  def recursive_fgrep_args
    # for GNU grep; overridden for BSD grep on OS X
    "-lr"
  end
  alias generic_recursive_fgrep_args recursive_fgrep_args

  def egrep_args
    grep_bin = "grep"
    grep_args = [
      "--files-with-matches",
      "--perl-regexp",
      "--binary-files=text",
    ]

    [grep_bin, grep_args]
  end
  alias generic_egrep_args egrep_args

  def each_unique_file_matching(string)
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

  def binary_file?(file)
    grep_bin, grep_args = egrep_args

    # We need to pass NULL_BYTE_STRING, the literal string "\x00", to grep
    # rather than NULL_BYTE, a literal null byte, because grep will internally
    # convert the literal string "\x00" to a null byte.
    Utils.popen_read(grep_bin, *grep_args, NULL_BYTE_STRING, file).present?
  end

  def lib
    path/"lib"
  end

  def libexec
    path/"libexec"
  end

  def text_files
    text_files = []
    return text_files if !which("file") || !which("xargs")

    # file has known issues with reading files on other locales. Has
    # been fixed upstream for some time, but a sufficiently new enough
    # file with that fix is only available in macOS Sierra.
    # https://bugs.gw.com/view.php?id=292
    with_custom_locale("C") do
      files = Set.new path.find.reject { |pn|
        next true if pn.symlink?
        next true if pn.directory?
        next false if pn.basename.to_s == "orig-prefix.txt" # for python virtualenvs
        next true if pn == self/".brew/#{name}.rb"
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

  def libtool_files
    libtool_files = []

    path.find do |pn|
      next if pn.symlink? || pn.directory? || Keg::LIBTOOL_EXTENSIONS.exclude?(pn.extname)

      libtool_files << pn
    end
    libtool_files
  end

  def symlink_files
    symlink_files = []
    path.find do |pn|
      symlink_files << pn if pn.symlink?
    end

    symlink_files
  end

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

  def self.file_linked_libraries(_file, _string)
    []
  end
end

require "extend/os/keg_relocate"
