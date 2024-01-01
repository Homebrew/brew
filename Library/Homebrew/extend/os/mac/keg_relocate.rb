# typed: true
# frozen_string_literal: true

class Keg
  class << self
    undef file_linked_libraries

    def file_linked_libraries(file, string)
      # Check dynamic library linkage. Importantly, do not perform for static
      # libraries, which will falsely report "linkage" to themselves.
      if file.mach_o_executable? || file.dylib? || file.mach_o_bundle?
        file.dynamically_linked_libraries.select { |lib| lib.include? string }
      else
        []
      end
    end
  end

  undef relocate_dynamic_linkage

  def relocate_dynamic_linkage(relocation)
    mach_o_files.each do |file|
      file.ensure_writable do
        modified = T.let(false, T::Boolean)
        needs_codesigning = T.let(false, T::Boolean)

        if file.dylib?
          id = relocated_name_for(file.dylib_id, relocation)
          modified = change_dylib_id(id, file)
          needs_codesigning ||= modified
        end

        each_linkage_for(file, :dynamically_linked_libraries) do |old_name|
          new_name = relocated_name_for(old_name, relocation)
          modified = change_install_name(old_name, new_name, file) if new_name
          needs_codesigning ||= modified
        end

        each_linkage_for(file, :rpaths) do |old_name|
          new_name = relocated_name_for(old_name, relocation)
          modified = change_rpath(old_name, new_name, file) if new_name
          needs_codesigning ||= modified
        end

        # codesign the file if needed
        codesign_patched_binary(file) if needs_codesigning
      end
    end
  end

  def fix_dynamic_linkage
    mach_o_files.each do |file|
      file.ensure_writable do
        modified = T.let(false, T::Boolean)
        needs_codesigning = T.let(false, T::Boolean)

        modified = change_dylib_id(dylib_id_for(file), file) if file.dylib?
        needs_codesigning ||= modified

        each_linkage_for(file, :dynamically_linked_libraries) do |bad_name|
          # Don't fix absolute paths unless they are rooted in the build directory.
          new_name = if bad_name.start_with?("/") && !rooted_in_build_directory?(bad_name)
            bad_name
          else
            fixed_name(file, bad_name)
          end
          loader_name = loader_name_for(file, new_name)
          modified = change_install_name(bad_name, loader_name, file) if loader_name != bad_name
          needs_codesigning ||= modified
        end

        each_linkage_for(file, :rpaths) do |bad_name|
          new_name = opt_name_for(bad_name)
          loader_name = loader_name_for(file, new_name)
          next if loader_name == bad_name

          modified = change_rpath(bad_name, loader_name, file)
          needs_codesigning ||= modified
        end

        # Strip duplicate rpaths and rpaths rooted in the build directory.
        # We do this separately from the rpath relocation above to avoid
        # failing to relocate an rpath whose variable duplicate we deleted.
        each_linkage_for(file, :rpaths, resolve_variable_references: true) do |bad_name|
          next if !rooted_in_build_directory?(bad_name) && file.rpaths.count(bad_name) == 1

          modified = delete_rpath(bad_name, file)
          needs_codesigning ||= modified
        end

        # codesign the file if needed
        codesign_patched_binary(file) if needs_codesigning
      end
    end

    generic_fix_dynamic_linkage
  end

  def loader_name_for(file, target)
    # Use @loader_path-relative install names for other Homebrew-installed binaries.
    if ENV["HOMEBREW_RELOCATABLE_INSTALL_NAMES"] && target.start_with?(HOMEBREW_PREFIX)
      dylib_suffix = find_dylib_suffix_from(target)
      target_dir = Pathname.new(target.delete_suffix(dylib_suffix)).cleanpath

      "@loader_path/#{target_dir.relative_path_from(file.dirname)/dylib_suffix}"
    else
      target
    end
  end

  # If file is a dylib or bundle itself, look for the dylib named by
  # bad_name relative to the lib directory, so that we can skip the more
  # expensive recursive search if possible.
  def fixed_name(file, bad_name)
    if bad_name.start_with? PREFIX_PLACEHOLDER
      bad_name.sub(PREFIX_PLACEHOLDER, HOMEBREW_PREFIX)
    elsif bad_name.start_with? CELLAR_PLACEHOLDER
      bad_name.sub(CELLAR_PLACEHOLDER, HOMEBREW_CELLAR)
    elsif (file.dylib? || file.mach_o_bundle?) && (file.dirname/bad_name).exist?
      "@loader_path/#{bad_name}"
    elsif file.mach_o_executable? && (lib/bad_name).exist?
      "#{lib}/#{bad_name}"
    elsif file.mach_o_executable? && (libexec/"lib"/bad_name).exist?
      "#{libexec}/lib/#{bad_name}"
    elsif (abs_name = find_dylib(bad_name)) && abs_name.exist?
      abs_name.to_s
    else
      opoo "Could not fix #{bad_name} in #{file}"
      bad_name
    end
  end

  VARIABLE_REFERENCE_RX = /^@(loader_|executable_|r)path/.freeze

  def each_linkage_for(file, linkage_type, resolve_variable_references: false, &block)
    file.public_send(linkage_type, resolve_variable_references: resolve_variable_references)
        .grep_v(VARIABLE_REFERENCE_RX)
        .each(&block)
  end

  def dylib_id_for(file)
    # The new dylib ID should have the same basename as the old dylib ID, not
    # the basename of the file itself.
    basename = File.basename(file.dylib_id)
    relative_dirname = file.dirname.relative_path_from(path)
    (opt_record/relative_dirname/basename).to_s
  end

  def relocated_name_for(old_name, relocation)
    old_prefix, new_prefix = relocation.replacement_pair_for(:prefix)
    old_cellar, new_cellar = relocation.replacement_pair_for(:cellar)

    if old_name.start_with? old_cellar
      old_name.sub(old_cellar, new_cellar)
    elsif old_name.start_with? old_prefix
      old_name.sub(old_prefix, new_prefix)
    end
  end

  # Matches framework references like `XXX.framework/Versions/YYY/XXX` and
  # `XXX.framework/XXX`, both with or without a slash-delimited prefix.
  FRAMEWORK_RX = %r{(?:^|/)(([^/]+)\.framework/(?:Versions/[^/]+/)?\2)$}.freeze

  def find_dylib_suffix_from(bad_name)
    if (framework = bad_name.match(FRAMEWORK_RX))
      framework[1]
    else
      File.basename(bad_name)
    end
  end

  def find_dylib(bad_name)
    return unless lib.directory?

    suffix = "/#{find_dylib_suffix_from(bad_name)}"
    lib.find { |pn| break pn if pn.to_s.end_with?(suffix) }
  end

  def mach_o_files
    hardlinks = Set.new
    mach_o_files = []
    path.find do |pn|
      next if pn.symlink? || pn.directory?
      next if !pn.dylib? && !pn.mach_o_bundle? && !pn.mach_o_executable?
      # if we've already processed a file, ignore its hardlinks (which have the same dev ID and inode)
      # this prevents relocations from being performed on a binary more than once
      next unless hardlinks.add? [pn.stat.dev, pn.stat.ino]

      mach_o_files << pn
    end

    mach_o_files
  end

  def prepare_relocation_to_locations
    relocation = generic_prepare_relocation_to_locations

    brewed_perl = runtime_dependencies&.any? { |dep| dep["full_name"] == "perl" && dep["declared_directly"] }
    perl_path = if brewed_perl || name == "perl"
      "#{HOMEBREW_PREFIX}/opt/perl/bin/perl"
    elsif tab.built_on.present?
      perl_path = "/usr/bin/perl#{tab.built_on["preferred_perl"]}"

      # For `:all` bottles, we could have built this bottle with a Perl we don't have.
      # Such bottles typically don't have strict version requirements.
      perl_path = "/usr/bin/perl#{MacOS.preferred_perl_version}" unless File.exist?(perl_path)

      perl_path
    else
      "/usr/bin/perl#{MacOS.preferred_perl_version}"
    end
    relocation.add_replacement_pair(:perl, PERL_PLACEHOLDER, perl_path)

    if (openjdk = openjdk_dep_name_if_applicable)
      openjdk_path = HOMEBREW_PREFIX/"opt"/openjdk/"libexec/openjdk.jdk/Contents/Home"
      relocation.add_replacement_pair(:java, JAVA_PLACEHOLDER, openjdk_path.to_s)
    end

    relocation
  end

  def recursive_fgrep_args
    # Don't recurse into symlinks; the man page says this is the default, but
    # it's wrong. -O is a BSD-grep-only option.
    "-lrO"
  end

  def egrep_args
    grep_bin = "egrep"
    grep_args = "--files-with-matches"
    [grep_bin, grep_args]
  end

  private

  CELLAR_RX = %r{\A#{HOMEBREW_CELLAR}/(?<formula_name>[^/]+)/[^/]+}.freeze

  # Replace HOMEBREW_CELLAR references with HOMEBREW_PREFIX/opt references
  # if the Cellar reference is to a different keg.
  def opt_name_for(filename)
    return filename unless filename.start_with?(HOMEBREW_PREFIX.to_s)
    return filename if filename.start_with?(path.to_s)
    return filename if (matches = CELLAR_RX.match(filename)).blank?

    filename.sub(CELLAR_RX, "#{HOMEBREW_PREFIX}/opt/#{matches[:formula_name]}")
  end

  def rooted_in_build_directory?(filename)
    # CMake normalises `/private/tmp` to `/tmp`.
    # https://gitlab.kitware.com/cmake/cmake/-/issues/23251
    return true if HOMEBREW_TEMP.to_s == "/private/tmp" && filename.start_with?("/tmp/")

    filename.start_with?(HOMEBREW_TEMP.to_s) || filename.start_with?(HOMEBREW_TEMP.realpath.to_s)
  end
end
