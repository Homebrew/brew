# typed: true
# frozen_string_literal: true

# Performs {Formula#mktemp}'s functionality, and tracks the results.
# Each instance is only intended to be used once.
class Mktemp
  include FileUtils

  # Path to the tmpdir used in this run, as a {Pathname}.
  attr_reader :tmpdir

  def initialize(prefix, opts = {})
    @prefix = prefix
    @retain_in_cache = opts[:retain_in_cache]
    @retain = opts[:retain] || @retain_in_cache
    @quiet = false
  end

  # Instructs this {Mktemp} to retain the staged files.
  sig { void }
  def retain!
    @retain = true
  end

  # True if the staged temporary files should be retained.
  def retain?
    @retain
  end

  # True if the source files should be retained.
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

  def run
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
    group_id = if HOMEBREW_BREW_FILE.grpowned?
      HOMEBREW_BREW_FILE.stat.gid
    else
      Process.gid
    end
    begin
      chown(nil, group_id, @tmpdir)
    rescue Errno::EPERM
      opoo "Failed setting group \"#{T.must(Etc.getgrgid(group_id)).name}\" on #{@tmpdir}"
    end

    begin
      Dir.chdir(tmpdir) { yield self }
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

  def chmod_rm_rf(path)
    if path.directory? && !path.symlink?
      chmod("u+rw", path) if path.owned? # Need permissions in order to see the contents
      path.children.each { |child| chmod_rm_rf(child) }
      rmdir(path)
    else
      rm_f(path)
    end
  rescue
    nil # Just skip this directory.
  end
end
