# typed: strict
# frozen_string_literal: true

require "utils/output"

class Keg
  extend Utils::Output::Mixin

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

  sig {
    params(_relocation: Relocation, with_placeholders: T::Boolean,
           files: T.nilable(T::Array[Pathname])).returns(T::Array[Pathname])
  }
  def relocate_dynamic_linkage(_relocation, with_placeholders: false, files: nil) = []

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

  sig { returns([T::Array[Pathname], T::Array[Pathname]]) }
  def replace_locations_with_placeholders
    relocation = prepare_relocation_to_placeholders.freeze
    linkage_files = relocate_dynamic_linkage(relocation, with_placeholders: true)
    [replace_text_in_files(relocation), linkage_files]
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

  sig {
    params(files: T.nilable(T::Array[Pathname]), skip_linkage: T::Boolean,
           linkage_files: T.nilable(T::Array[Pathname])).void
  }
  def replace_placeholders_with_locations(files, skip_linkage: false, linkage_files: nil)
    relocation = prepare_relocation_to_locations.freeze
    relocate_dynamic_linkage(relocation, files: linkage_files) unless skip_linkage
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

  # Returns the patched files relative to the keg.
  sig {
    params(keg: Keg, old_prefix: T.any(String, Pathname), new_prefix: T.any(String, Pathname),
           files: T.nilable(T::Array[Pathname])).returns(T::Array[Pathname])
  }
  def relocate_build_prefix(keg, old_prefix, new_prefix, files: nil)
    old_prefix = old_prefix.to_s
    new_prefix = new_prefix.to_s
    # A raw C string can only be replaced in place by an equal-or-shorter
    # string, so refuse before touching any file rather than failing midway.
    if new_prefix.bytesize > old_prefix.bytesize
      raise ArgumentError, "Cannot relocate build prefix #{old_prefix} to longer prefix #{new_prefix}"
    end

    # Hardlinked names share one inode: patch it once through the first name
    # and re-link the rest afterwards, as the patched file gets a new inode.
    inode_groups = if files
      # Metadata-driven pour: only the files recorded at bottle time carry raw
      # prefix strings, so skip the whole-keg scan.
      files.map { |relative_path| path/relative_path }
           .select { |file| file.file? && !file.symlink? }
           .group_by { |file| file.stat.ino }
           .values
    else
      files_matching_by_inode(old_prefix)
    end

    patched_groups = T.let([], T::Array[T::Array[Pathname]])
    inode_groups.each do |group|
      file = group.fetch(0)
      # Skip files which are not binary, as they do not need null padding.
      next unless keg.binary_file?(file)

      # Skip sharballs, which appear to break if patched.
      next if file.text_executable?

      # Split binary by null characters into array and substitute new prefix for old prefix.
      # Null padding is added if the new string is too short.
      file.ensure_writable do
        binary = File.binread file
        binary_strings = binary.split(/#{NULL_BYTE}/o, -1)
        match_indices = binary_strings.each_index.select { |i| binary_strings.fetch(i).include?(old_prefix) }

        # Bottle metadata records files pinned by any prefix, cellar or
        # repository reference, so a recorded file may not contain this
        # particular string and must not be rewritten or re-signed.
        next if match_indices.empty?

        odebug "Replacing build prefix in: #{file}"

        # Linkers merge a string with the suffix of another, so a string in
        # the dynamic string table can be referenced from its interior.
        interior_references = Keg.elf_dynamic_string_references_in(file)
        string_starts = T.let([], T::Array[Integer])
        binary_strings.reduce(0) do |start, binary_string|
          string_starts << start
          start + binary_string.bytesize + 1
        end

        match_indices.each do |i|
          binary_string = binary_strings.fetch(i)
          start = string_starts.fetch(i)
          preserve_suffix_offsets = interior_references.any? do |reference|
            reference > start && reference < start + binary_string.bytesize
          end
          binary_strings[i] = Keg.replace_prefix_preserving_length(binary_string, old_prefix, new_prefix,
                                                                   preserve_suffix_offsets:)
        end

        # Rejoin strings by null bytes.
        patched_binary = binary_strings.join(NULL_BYTE)
        if patched_binary.bytesize != binary.bytesize
          raise <<~EOS
            Patching failed!  Original and patched binary sizes do not match.
            Original size: #{binary.bytesize}
            Patched size: #{patched_binary.bytesize}
          EOS
        end

        file.atomic_write patched_binary
        patched_groups << group
      end
    end

    # Each patch broke the file's signature, so re-sign each patched file
    # exactly once, parallelised across files.
    codesign_patched_binaries(patched_groups.map { |group| group.fetch(0) })

    patched_groups.each do |group|
      first = group.fetch(0)
      group.drop(1).each { |file| FileUtils.ln(first, file, force: true) }
    end

    patched_groups.flatten.map { |file| file.relative_path_from(path) }
  end

  # Replaces the prefix in a NUL-terminated string without changing its
  # length. Trailing NUL padding is invisible to C string readers but shifts
  # any suffix-merged reference into the string, so when the string has such
  # references and the prefix is followed by a path separator, pad with
  # extra separators instead: path resolution treats `//` as `/`.
  sig {
    params(string: String, old_prefix: String, new_prefix: String, preserve_suffix_offsets: T::Boolean).returns(String)
  }
  def self.replace_prefix_preserving_length(string, old_prefix, new_prefix, preserve_suffix_offsets:)
    if preserve_suffix_offsets
      separators = "/" * (old_prefix.bytesize - new_prefix.bytesize + 1)
      padded = string.gsub("#{old_prefix}/") { "#{new_prefix}#{separators}" }
      return padded if padded.bytesize == string.bytesize
    end

    string.gsub(old_prefix) { new_prefix }.ljust(string.bytesize, NULL_BYTE)
  end

  # Absolute file offsets of the strings the dynamic loader references in
  # the file's dynamic string table, or none for files that are not ELF or
  # cannot be parsed.
  sig { params(file: Pathname).returns(T::Array[Integer]) }
  def self.elf_dynamic_string_references_in(file)
    require "os/linux/elf"
    return [] unless T.cast(Pathname.new(file.to_s).extend(ELFShim), ELFShim).elf?

    require "elftools"
    file.open("rb") do |stream|
      elf_dynamic_string_references(ELFTools::ELFFile.new(stream))&.offsets || []
    end
  rescue ELFTools::ELFError, IOError, SystemCallError
    []
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

  # Files containing the string, grouped by inode so that hardlinks to the
  # same file appear together.
  sig { params(string: T.any(String, Pathname)).returns(T::Array[T::Array[Pathname]]) }
  def files_matching_by_inode(string)
    files = T.let([], T::Array[Pathname])
    Utils.popen_read("fgrep", recursive_fgrep_args, string, to_s) do |io|
      until io.eof?
        file = Pathname.new(io.readline.chomp)
        # Don't return symbolic links.
        files << file unless file.symlink?
      end
    end
    files.group_by { |file| file.stat.ino }.values
  end

  sig { params(string: T.any(String, Pathname), block: T.proc.params(arg0: Pathname).void).void }
  def each_unique_file_matching(string, &block)
    # Hardlinks share an inode with the file they point to, so only the first
    # name of each inode is yielded.
    files_matching_by_inode(string).map { |group| group.fetch(0) }.each(&block)
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
    params(file: Pathname, string: String, ignores: T::Array[Regexp], linked_libraries: T::Array[String],
           formula_and_runtime_deps_names: T.nilable(T::Array[String])).returns(T::Array[[String, String]])
  }
  def self.text_matches_in_file(file, string, ignores, linked_libraries, formula_and_runtime_deps_names)
    text_matches = []
    path_regex = Relocation.path_to_regex(string)
    each_candidate_string(file, string) do |(offset, match)|
      next if ignores.any? { |i| match.match?(i) }
      next unless match.match? path_regex

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
    text_matches
  end

  # Yields each printable string in the file with its hexadecimal offset, as
  # `strings -t x` reports them. ELF files yield only the strings the loader
  # or the program can reach, see `elf_relocation_strings`.
  sig { params(file: Pathname, string: String, block: T.proc.params(candidate: [String, String]).void).void }
  def self.each_candidate_string(file, string, &block)
    if (elf_strings = elf_relocation_strings(file, string))
      elf_strings.each(&block)
      return
    end

    Utils.popen_read("strings", "-t", "x", "-", file.to_s) do |io|
      until io.eof?
        line = io.readline.chomp
        offset, match = line.split(" ", 2)
        odie "Failed to parse strings output: #{line.inspect}" if offset.nil? || match.nil?

        yield [offset, match]
      end
    end
  end

  # Runs of at least four printable bytes, as `strings` reports by default.
  PRINTABLE_RUN_REGEX = /[\t\x20-\x7e]{4,}/n
  private_constant :PRINTABLE_RUN_REGEX

  # Build tools leave dead prefix strings in ELF files: Meson's install-time
  # RPATH fixer overwrites the build RPATH with the shorter install RPATH
  # without clearing the rest of the old string, and patchelf moves the
  # dynamic string table or interpreter when growing them, leaving the old
  # copy behind. A whole-file `strings` scan still finds those bytes and
  # wrongly pins bottles whose live linkage is fully placeholdered. ELF files
  # are therefore scanned by structure rather than as a whole: the interpreter the
  # loader uses, the dynamic strings the loader references and the contents of
  # the remaining sections. Bytes outside every section and unreferenced
  # entries in loader-owned string tables are never candidates.
  #
  # This deliberately errs towards relocatability (design decision 11 in
  # `plans/relocatable-bottles.md`): a wrongly pinned bottle forces source
  # builds for every non-default-prefix user, whereas a wrongly accepted one
  # surfaces as a per-formula bug report and fix.
  #
  # Returns nil, so that the whole file is scanned instead, for files that are
  # not ELF, cannot name their sections or whose tables are truncated.
  sig { params(file: Pathname, string: String).returns(T.nilable(T::Array[[String, String]])) }
  def self.elf_relocation_strings(file, string)
    require "os/linux/elf"
    return unless T.cast(Pathname.new(file.to_s).extend(ELFShim), ELFShim).elf?

    require "elftools"
    require "strscan"

    stream = file.open("rb")
    begin
      elf = ELFTools::ELFFile.new(stream)
      # A file may legally keep section headers while `e_shstrndx` is
      # `SHN_UNDEF` (no section-name table); sections cannot be told apart
      # without names.
      return unless elf.strtab_section.is_a?(ELFTools::Sections::StrTabSection)

      strings = T.let([], T::Array[[Integer, String]])

      if (interp = elf.segment_by_type(:interp))
        strings << [interp.header.p_offset.to_i, interp.interp_name]
      end

      string_table_range = T.let(nil, T.nilable(T::Range[Integer]))
      if (references = elf_dynamic_string_references(elf))
        string_table_range = references.string_table_range
        referenced_offsets = references.offsets
        # A referenced string runs from its offset to the terminating NUL,
        # so a suffix-merged reference to the interior `libfoo.so` of
        # `/old/prefix/libfoo.so` never yields the dead prefix before it.
        referenced_offsets.each do |offset|
          stream.pos = offset
          referenced = stream.gets("\0")&.delete_suffix("\0")
          strings << [offset, referenced] if referenced
        end
      end

      # Everything else the program itself can reach: the contents of the
      # remaining sections. Loader-owned string regions are covered above and
      # bytes outside every section are deliberately excluded from relocation.
      elf.sections.each do |section|
        header = section.header
        # SHT_NOBITS sections (e.g. `.bss`) occupy no file bytes.
        next if header.sh_type.to_i == ELFTools::Constants::SHT::SHT_NOBITS
        next if header.sh_size.to_i.zero?
        next if [".dynstr", ".interp"].include?(section.name)

        section_start = header.sh_offset.to_i
        next if string_table_range&.cover?(section_start)

        data = section.data
        # Cheap pre-check before extracting every printable run.
        next unless data.include?(string)

        scanner = StringScanner.new(data)
        while scanner.skip_until(PRINTABLE_RUN_REGEX)
          run = scanner.matched
          strings << [section_start + scanner.pos - run.bytesize, run]
        end
      end

      strings.filter_map do |offset, match|
        next unless match.ascii_only?

        [offset.to_s(16), match.force_encoding(Encoding::UTF_8)]
      end
    ensure
      stream.close
    end
  rescue ELFTools::ELFError, IOError, SystemCallError
    # Not valid ELF, or program, section or dynamic tables truncated or
    # pointing outside the file mid-parse (Linux raises `Errno::EINVAL`
    # for the resulting seek where macOS returns EOF).
    nil
  end

  class DynamicStringReferences < T::Struct
    # The file range of the dynamic string table, when its size is known.
    const :string_table_range, T.nilable(T::Range[Integer])
    # Absolute file offsets of the strings the loader references in it.
    const :offsets, T::Array[Integer]
  end

  # The strings the dynamic loader references in the file's dynamic string
  # table, or nil without a dynamic segment or string table.
  sig { params(elf: ELFTools::ELFFile).returns(T.nilable(DynamicStringReferences)) }
  def self.elf_dynamic_string_references(elf)
    dynamic = elf.segment_by_type(:dynamic)
    return if dynamic.nil?

    # Dynamic tags whose value is an offset into the dynamic string table,
    # i.e. the strings the loader can actually see.
    string_tags = [
      ELFTools::Constants::DT::DT_NEEDED,
      ELFTools::Constants::DT::DT_SONAME,
      ELFTools::Constants::DT::DT_RPATH,
      ELFTools::Constants::DT::DT_RUNPATH,
      ELFTools::Constants::DT::DT_AUXILIARY,
      # elftools 1.3.1 mislabels `DT_USED` (0x7ffffffe) as `DT_FILTER`;
      # both hold string-table offsets, so keep the mislabelled value
      # and add the ELF ABI's real `DT_FILTER`.
      ELFTools::Constants::DT::DT_FILTER,
      0x7fffffff, # DT_FILTER
      ELFTools::Constants::DT::DT_AUDIT,
      ELFTools::Constants::DT::DT_DEPAUDIT,
      ELFTools::Constants::DT::DT_CONFIG,
    ]
    string_table_vaddr = T.let(nil, T.nilable(Integer))
    string_table_size = T.let(nil, T.nilable(Integer))
    string_offsets = []
    dynamic.tags.each do |tag|
      case tag.header.d_tag.to_i
      when ELFTools::Constants::DT::DT_STRTAB then string_table_vaddr = tag.header.d_val.to_i
      when ELFTools::Constants::DT::DT_STRSZ then string_table_size = tag.header.d_val.to_i
      when *string_tags then string_offsets << tag.header.d_val.to_i
      end
    end
    return if string_table_vaddr.nil?

    string_table_offset = elf.offset_from_vma(string_table_vaddr)
    return if string_table_offset.nil?

    # Dynamic symbol names are loader-visible strings in the same table,
    # referenced by `.dynsym` `st_name` rather than by dynamic tags. Version
    # table strings also index the table but hold version names, never
    # paths, so they are not collected.
    elf.sections_by_type(ELFTools::Constants::SHT::SHT_DYNSYM).each do |section|
      section.symbols.each do |symbol|
        name_offset = symbol.header.st_name.to_i
        string_offsets << name_offset unless name_offset.zero?
      end
    end

    string_table_range = string_table_offset...(string_table_offset + string_table_size) if string_table_size
    DynamicStringReferences.new(string_table_range:,
                                offsets:            string_offsets.uniq.map { |offset| string_table_offset + offset })
  end

  sig { params(_file: Pathname, _string: String).returns(T::Array[String]) }
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
