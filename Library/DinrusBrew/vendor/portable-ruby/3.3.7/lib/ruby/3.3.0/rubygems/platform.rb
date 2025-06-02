# frozen_string_literal: true

require_relative "deprecate"

##
# Available list of platforms for targeting Gem installations.
#
# See `gem help platform` for information on platform matching.

class Gem::Platform
  @local = nil

  attr_accessor :cpu, :os, :version

  def self.local
    @local ||= begin
      arch = RbConfig::CONFIG["arch"]
      arch = "#{arch}_60" if /mswin(?:32|64)$/.match?(arch)
      new(arch)
    end
  end

  def self.match(platform)
    match_platforms?(platform, Gem.platforms)
  end

  class << self
    extend Gem::Deprecate
    rubygems_deprecate :match, "Gem::Platform.match_spec? or match_gem?"
  end

  def self.match_platforms?(platform, platforms)
    platform = Gem::Platform.new(platform) unless platform.is_a?(Gem::Platform)
    platforms.any? do |local_platform|
      platform.nil? ||
        local_platform == platform ||
        (local_platform != Gem::Platform::RUBY && platform =~ local_platform)
    end
  end
  private_class_method :match_platforms?

  def self.match_spec?(spec)
    match_gem?(spec.platform, spec.name)
  end

  if RUBY_ENGINE == "truffleruby"
    def self.match_gem?(platform, gem_name)
      raise "Not a string: #{gem_name.inspect}" unless String === gem_name

      if REUSE_AS_BINARY_ON_TRUFFLERUBY.include?(gem_name)
        match_platforms?(platform, [Gem::Platform::RUBY, Gem::Platform.local])
      else
        match_platforms?(platform, Gem.platforms)
      end
    end
  else
    def self.match_gem?(platform, gem_name)
      match_platforms?(platform, Gem.platforms)
    end
  end

  def self.sort_priority(platform)
    platform == Gem::Platform::RUBY ? -1 : 1
  end

  def self.installable?(spec)
    if spec.respond_to? :installable_platform?
      spec.installable_platform?
    else
      match_spec? spec
    end
  end

  def self.new(arch) # :nodoc:
    case arch
    when Gem::Platform::CURRENT then
      Gem::Platform.local
    when Gem::Platform::RUBY, nil, "" then
      Gem::Platform::RUBY
    else
      super
    end
  end

  def initialize(arch)
    case arch
    when Array then
      @cpu, @os, @version = arch
    when String then
      arch = arch.split "-"

      if arch.length > 2 && !arch.last.match?(/\d+(\.\d+)?$/) # reassemble x86-linux-{libc}
        extra = arch.pop
        arch.last << "-#{extra}"
      end

      cpu = arch.shift

      @cpu = case cpu
             when /i\d86/ then "x86"
             else cpu
      end

      if arch.length == 2 && arch.last.match?(/^\d+(\.\d+)?$/) # for command-line
        @os, @version = arch
        return
      end

      os, = arch
      if os.nil?
        @cpu = nil
        os = cpu
      end # legacy jruby

      @os, @version = case os
                      when /aix(\d+)?/ then             ["aix",       $1]
                      when /cygwin/ then                ["cygwin",    nil]
                      when /darwin(\d+)?/ then          ["darwin",    $1]
                      when /^macruby$/ then             ["macruby",   nil]
                      when /freebsd(\d+)?/ then         ["freebsd",   $1]
                      when /^java$/, /^jruby$/ then     ["java",      nil]
                      when /^java([\d.]*)/ then         ["java",      $1]
                      when /^dalvik(\d+)?$/ then        ["dalvik",    $1]
                      when /^dotnet$/ then              ["dotnet",    nil]
                      when /^dotnet([\d.]*)/ then       ["dotnet",    $1]
                      when /linux-?(\w+)?/ then         ["linux",     $1]
                      when /mingw32/ then               ["mingw32",   nil]
                      when /mingw-?(\w+)?/ then         ["mingw",     $1]
                      when /(mswin\d+)(\_(\d+))?/ then
                        os = $1
                        version = $3
                        @cpu = "x86" if @cpu.nil? && os =~ /32$/
                        [os, version]
                      when /netbsdelf/ then             ["netbsdelf", nil]
                      when /openbsd(\d+\.\d+)?/ then    ["openbsd",   $1]
                      when /solaris(\d+\.\d+)?/ then    ["solaris",   $1]
                      when /wasi/ then                  ["wasi",      nil]
                      # test
                      when /^(\w+_platform)(\d+)?/ then [$1,          $2]
                      else ["unknown", nil]
      end
    when Gem::Platform then
      @cpu = arch.cpu
      @os = arch.os
      @version = arch.version
    else
      raise ArgumentError, "invalid argument #{arch.inspect}"
    end
  end

  def to_a
    [@cpu, @os, @version]
  end

  def to_s
    to_a.compact.join "-"
  end

  ##
  # Is +other+ equal to this platform?  Two platforms are equal if they have
  # the same CPU, OS and version.

  def ==(other)
    self.class === other && to_a == other.to_a
  end

  alias_method :eql?, :==

  def hash # :nodoc:
    to_a.hash
  end

  ##
  # Does +other+ match this platform?  Two platforms match if they have the
  # same CPU, or either has a CPU of 'universal', they have the same OS, and
  # they have the same version, or either one has no version
  #
  # Additionally, the platform will match if the local CPU is 'arm' and the
  # other CPU starts with "armv" (for generic 32-bit ARM family support).
  #
  # Of note, this method is not commutative. Indeed the OS 'linux' has a
  # special case: the version is the libc name, yet while "no version" stands
  # as a wildcard for a binary gem platform (as for other OSes), for the
  # runtime platform "no version" stands for 'gnu'. To be able to distinguish
  # these, the method receiver is the gem platform, while the argument is
  # the runtime platform.
  #
  #--
  # NOTE: Until it can be removed, changes to this method must also be reflected in `bundler/lib/bundler/rubygems_ext.rb`

  def ===(other)
    return nil unless Gem::Platform === other

    # universal-mingw32 matches x64-mingw-ucrt
    return true if (@cpu == "universal" || other.cpu == "universal") &&
                   @os.start_with?("mingw") && other.os.start_with?("mingw")

    # cpu
    ([nil,"universal"].include?(@cpu) || [nil, "universal"].include?(other.cpu) || @cpu == other.cpu ||
    (@cpu == "arm" && other.cpu.start_with?("armv"))) &&

      # os
      @os == other.os &&

      # version
      (
        (@os != "linux" && (@version.nil? || other.version.nil?)) ||
        (@os == "linux" && (normalized_linux_version == other.normalized_linux_version || ["musl#{@version}", "musleabi#{@version}", "musleabihf#{@version}"].include?(other.version))) ||
        @version == other.version
      )
  end

  #--
  # NOTE: Until it can be removed, changes to this method must also be reflected in `bundler/lib/bundler/rubygems_ext.rb`

  def normalized_linux_version
    return nil unless @version

    without_gnu_nor_abi_modifiers = @version.sub(/\Agnu/, "").sub(/eabi(hf)?\Z/, "")
    return nil if without_gnu_nor_abi_modifiers.empty?

    without_gnu_nor_abi_modifiers
  end

  ##
  # Does +other+ match this platform?  If +other+ is a String it will be
  # converted to a Gem::Platform first.  See #=== for matching rules.

  def =~(other)
    case other
    when Gem::Platform then # nop
    when String then
      # This data is from http://gems.rubyforge.org/gems/yaml on 19 Aug 2007
      other = case other
              when /^i686-darwin(\d)/     then ["x86",       "darwin",  $1]
              when /^i\d86-linux/         then ["x86",       "linux",   nil]
              when "java", "jruby"        then [nil,         "java",    nil]
              when /^dalvik(\d+)?$/       then [nil,         "dalvik",  $1]
              when /dotnet(\-(\d+\.\d+))?/ then ["universal","dotnet",  $2]
              when /mswin32(\_(\d+))?/    then ["x86",       "mswin32", $2]
              when /mswin64(\_(\d+))?/    then ["x64",       "mswin64", $2]
              when "powerpc-darwin"       then ["powerpc",   "darwin",  nil]
              when /powerpc-darwin(\d)/   then ["powerpc",   "darwin",  $1]
              when /sparc-solaris2.8/     then ["sparc",     "solaris", "2.8"]
              when /universal-darwin(\d)/ then ["universal", "darwin",  $1]
              else other
      end

      other = Gem::Platform.new other
    else
      return nil
    end

    self === other
  end

  ##
  # A pure-Ruby gem that may use Gem::Specification#extensions to build
  # binary files.

  RUBY = "ruby"

  ##
  # A platform-specific gem that is built for the packaging Ruby's platform.
  # This will be replaced with Gem::Platform::local.

  CURRENT = "current"
end
