# typed: strict
# frozen_string_literal: true

require "utils/output"

# Performs {Formula#mktemp}'s functionality and tracks the results.
# Each instance is only intended to be used once.
# Can also be used to create a temporary directory with the brew instance's group.
class Mktemp
  include Utils::Output::Mixin

  # Path to the tmpdir used in this run
  sig { returns(T.nilable(Pathname)) }
  attr_reader :tmpdir

  sig { params(prefix: String, retain: T::Boolean, retain_in_cache: T::Boolean).void }
  def initialize(prefix, retain: false, retain_in_cache: false)
    @prefix = prefix
    @retain_in_cache = retain_in_cache
    @retain = T.let(retain || @retain_in_cache, T::Boolean)
    @quiet = T.let(false, T::Boolean)
    @tmpdir = T.let(nil, T.nilable(Pathname))
  end

  # Instructs this {Mktemp} to retain the staged files.
  sig { void }
  def retain!
    @retain = true
  end

  # True if the staged temporary files should be retained.
  sig { returns(T::Boolean) }
  def retain?
    @retain
  end

  # True if the source files should be retained.
  sig { returns(T::Boolean) }
  def retain_in_cache?
    @retain_in_cache
  end

  # Instructs this Mktemp to not emit messages when retention is triggered.
  sig { void }
  def quiet!
    @quiet = true
  end

  sig { returns(String) }
  def to_s
    "[Mktemp: #{tmpdir} retain=#{@retain} quiet=#{@quiet}]"
  end

  sig {
    type_parameters(:U).params(
      chdir:  T::Boolean,
      _block: T.proc.params(arg0: Mktemp).returns(T.type_parameter(:U)),
    ).returns(T.type_parameter(:U))
  }
  def run(chdir: true, &_block)
    prefix_name = @prefix.tr "@", "AT"
    @tmpdir = if retain_in_cache?
      tmp_dir = HOMEBREW_CACHE/"Sources/#{prefix_name}"
      chmod_rm_rf(tmp_dir) # clear out previous staging directory
      tmp_dir.mkpath
      tmp_dir
    else
      Pathname.new(Dir.mktmpdir("#{prefix_name}-", HOMEBREW_TEMP))
    end

    # Make sure files inside the temporary directory have the same group as the
    # brew instance.
    #
    # Reference from `man 2 open`
    # > When a new file is created, it is given the group of the directory which
    # contains it.
    group_id = if HOMEBREW_ORIGINAL_BREW_FILE.grpowned?
      HOMEBREW_ORIGINAL_BREW_FILE.stat.gid
    else
      Process.gid
    end
    begin
      @tmpdir.chown(nil, group_id)
    rescue Errno::EPERM
      require "etc"
      group_name = begin
        Etc.getgrgid(group_id)&.name
      rescue ArgumentError
        # Cover for misconfigured NSS setups
        nil
      end
      opoo "Failed setting group \"#{group_name || group_id}\" on #{@tmpdir}"
    end

    begin
      if chdir
        Dir.chdir(@tmpdir) { yield self }
      else
        yield self
      end
    ensure
      ignore_interrupts { chmod_rm_rf(@tmpdir) } unless retain?
    end
  ensure
    if retain? && @tmpdir.present? && !@quiet
      message = retain_in_cache? ? "Source files for debugging available at:" : "Temporary files retained at:"
      ohai message, @tmpdir.to_s
    end
  end

  private

  sig { params(path: Pathname).void }
  def chmod_rm_rf(path)
    if path.directory? && !path.symlink?
      FileUtils.chmod("u+rw", path) if path.owned? # Need permissions in order to see the contents
      path.children.each { |child| chmod_rm_rf(child) }
      FileUtils.rmdir(path)
    else
      FileUtils.rm_f(path)
    end
  rescue
    nil # Just skip this directory.
  end
end
