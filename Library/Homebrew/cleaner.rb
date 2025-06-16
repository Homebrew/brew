# typed: strict
# frozen_string_literal: true

# Cleans a newly installed keg.
# By default:
#
# * removes `.la` files
# * removes `.tbd` files
# * removes `perllocal.pod` files
# * removes `.packlist` files
# * removes empty directories
# * sets permissions on executables
# * removes unresolved symlinks
class Cleaner
  include Context

  # Create a cleaner for the given formula.
  sig { params(formula: Formula).void }
  def initialize(formula)
    @formula = formula
  end

  # Clean the keg of the formula.
  sig { void }
  def clean
    ObserverPathnameExtension.reset_counts!

    # Many formulae include `lib/charset.alias`, but it is not strictly needed
    # and will conflict if more than one formula provides it.
    observe_file_removal @formula.lib/"charset.alias"

    [@formula.bin, @formula.sbin, @formula.lib].each { |dir| clean_dir(dir) if dir.exist? }

    # Get rid of any info `dir` files, so they don't conflict at the link stage.
    #
    # The `dir` files come in at least 3 locations:
    #
    # 1. `info/dir`
    # 2. `info/#{name}/dir`
    # 3. `info/#{arch}/dir`
    #
    # Of these 3 only `info/#{name}/dir` is safe to keep since the rest will
    # conflict with other formulae because they use a shared location.
    #
    # See
    # [cleaner: recursively delete info `dir`s][1],
    # [emacs 28.1 bottle does not contain `dir` file][2] and
    # [Keep `info/#{f.name}/dir` files in cleaner][3]
    # for more info.
    #
    # [1]: https://github.com/Homebrew/brew/pull/11597
    # [2]: https://github.com/Homebrew/homebrew-core/issues/100190
    # [3]: https://github.com/Homebrew/brew/pull/13215
    @formula.info.glob("**/dir").each do |info_dir_file|
      next unless info_dir_file.file?
      next if info_dir_file == @formula.info/@formula.name/"dir"
      next if @formula.skip_clean?(info_dir_file)

      observe_file_removal info_dir_file
    end

    rewrite_shebangs
    clean_python_metadata

    prune
  end

  private

  sig { params(path: Pathname).void }
  def observe_file_removal(path)
    path.extend(ObserverPathnameExtension).unlink if path.exist?
  end

  # Removes any empty directories in the formula's prefix subtree
  # Keeps any empty directories protected by skip_clean
  # Removes any unresolved symlinks
  sig { void }
  def prune
    dirs = []
    symlinks = []
    @formula.prefix.find do |path|
      if path == @formula.libexec || @formula.skip_clean?(path)
        Find.prune
      elsif path.symlink?
        symlinks << path
      elsif path.directory?
        dirs << path
      end
    end

    # Remove directories opposite from traversal, so that a subtree with no
    # actual files gets removed correctly.
    dirs.reverse_each do |d|
      if d.children.empty?
        puts "rmdir: #{d} (empty)" if verbose?
        d.rmdir
      end
    end

    # Remove unresolved symlinks
    symlinks.reverse_each do |s|
      s.unlink unless s.resolved_path_exists?
    end
  end

  sig { params(path: Pathname).returns(T::Boolean) }
  def executable_path?(path)
    path.text_executable? || path.executable?
  end

  # Both these files are completely unnecessary to package and cause
  # pointless conflicts with other formulae. They are removed by Debian,
  # Arch & MacPorts amongst other packagers as well. The files are
  # created as part of installing any Perl module.
  PERL_BASENAMES = T.let(Set.new(%w[perllocal.pod .packlist]).freeze, T::Set[String])
  private_constant :PERL_BASENAMES

  # Clean a top-level (`bin`, `sbin`, `lib`) directory, recursively, by fixing file
  # permissions and removing .la files, unless the files (or parent
  # directories) are protected by skip_clean.
  #
  # `bin` and `sbin` should not have any subdirectories; if either do that is
  # caught as an audit warning.
  #
  # `lib` may have a large directory tree (see Erlang for instance) and
  # clean_dir applies cleaning rules to the entire tree.
  sig { params(directory: Pathname).void }
  def clean_dir(directory)
    directory.find do |path|
      path.extend(ObserverPathnameExtension)

      Find.prune if @formula.skip_clean? path

      next if path.directory?

      if path.extname == ".la" || path.extname == ".tbd" || PERL_BASENAMES.include?(path.basename.to_s)
        path.unlink
      elsif path.symlink?
        # Skip it.
      else
        # Set permissions for executables and non-executables.
        perms = if executable_path?(path)
          0555
        else
          0444
        end
        if debug?
          old_perms = path.stat.mode & 0777
          odebug "Fixing #{path} permissions from #{old_perms.to_s(8)} to #{perms.to_s(8)}" if perms != old_perms
        end
        path.chmod perms
      end
    end
  end

  sig { void }
  def rewrite_shebangs
    require "language/node"
    require "language/perl"
    require "utils/shebang"

    rewrites = [Language::Node::Shebang.method(:detected_node_shebang),
                Language::Perl::Shebang.method(:detected_perl_shebang)].filter_map do |detector|
      detector.call(@formula)
    rescue ShebangDetectionError
      nil
    end
    return if rewrites.empty?

    basepath = @formula.prefix.realpath
    basepath.find do |path|
      Find.prune if @formula.skip_clean? path

      next if path.directory? || path.symlink?

      rewrites.each { |rw| Utils::Shebang.rewrite_shebang rw, path }
    end
  end

  # Remove non-reproducible pip direct_url.json which records the /tmp build directory.
  # Remove RECORD files to prevent changes to the installed Python package.
  # Modify INSTALLER to provide information that files are managed by brew.
  #
  # @see https://packaging.python.org/en/latest/specifications/recording-installed-packages/
  sig { void }
  def clean_python_metadata
    basepath = @formula.prefix.realpath
    basepath.find do |path|
      Find.prune if @formula.skip_clean?(path)

      next if path.directory? || path.symlink?
      next if path.parent.extname != ".dist-info"

      case path.basename.to_s
      when "direct_url.json", "RECORD"
        observe_file_removal path
      when "INSTALLER"
        odebug "Modifying #{path} contents from #{path.read.chomp} to brew"
        path.atomic_write("brew\n")
      end
    end
  end
end

require "extend/os/cleaner"
