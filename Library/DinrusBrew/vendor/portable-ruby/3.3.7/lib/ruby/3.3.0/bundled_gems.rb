# -*- frozen-string-literal: true -*-

# :stopdoc:

module Gem::BUNDLED_GEMS
  SINCE = {
    "rexml" => "3.0.0",
    "rss" => "3.0.0",
    "webrick" => "3.0.0",
    "matrix" => "3.1.0",
    "net-ftp" => "3.1.0",
    "net-imap" => "3.1.0",
    "net-pop" => "3.1.0",
    "net-smtp" => "3.1.0",
    "prime" => "3.1.0",
    "racc" => "3.3.0",
    "abbrev" => "3.4.0",
    "base64" => "3.4.0",
    "bigdecimal" => "3.4.0",
    "csv" => "3.4.0",
    "drb" => "3.4.0",
    "getoptlong" => "3.4.0",
    "mutex_m" => "3.4.0",
    "nkf" => "3.4.0",
    "observer" => "3.4.0",
    "resolv-replace" => "3.4.0",
    "rinda" => "3.4.0",
    "syslog" => "3.4.0",
  }.freeze

  SINCE_FAST_PATH = SINCE.transform_keys { |g| g.sub(/\A.*\-/, "") }.freeze

  EXACT = {
    "kconv" => "nkf",
  }.freeze

  PREFIXED = {
    "bigdecimal" => true,
    "csv" => true,
    "drb" => true,
    "rinda" => true,
    "syslog" => true,
  }.freeze

  WARNED = {}                   # unfrozen

  conf = ::RbConfig::CONFIG
  LIBDIR = (conf["rubylibdir"] + "/").freeze
  ARCHDIR = (conf["rubyarchdir"] + "/").freeze
  dlext = [conf["DLEXT"], "so"].uniq
  DLEXT = /\.#{Regexp.union(dlext)}\z/
  LIBEXT = /\.#{Regexp.union("rb", *dlext)}\z/

  def self.replace_require(specs)
    return if [::Kernel.singleton_class, ::Kernel].any? {|klass| klass.respond_to?(:no_warning_require) }

    spec_names = specs.to_a.each_with_object({}) {|spec, h| h[spec.name] = true }

    [::Kernel.singleton_class, ::Kernel].each do |kernel_class|
      kernel_class.send(:alias_method, :no_warning_require, :require)
      kernel_class.send(:define_method, :require) do |name|
        if message = ::Gem::BUNDLED_GEMS.warning?(name, specs: spec_names)
          if ::Gem::BUNDLED_GEMS.uplevel > 0
            Kernel.warn message, uplevel: ::Gem::BUNDLED_GEMS.uplevel
          else
            Kernel.warn message
          end
        end
        kernel_class.send(:no_warning_require, name)
      end
      if kernel_class == ::Kernel
        kernel_class.send(:private, :require)
      else
        kernel_class.send(:public, :require)
      end
    end
  end

  def self.uplevel
    frame_count = 0
    frames_to_skip = 3
    uplevel = 0
    require_found = false
    Thread.each_caller_location do |cl|
      frame_count += 1
      if frames_to_skip >= 1
        frames_to_skip -= 1
        next
      end
      uplevel += 1
      if require_found
        if cl.base_label != "require"
          return uplevel
        end
      else
        if cl.base_label == "require"
          require_found = true
        end
      end
      # Don't show script name when bundle exec and call ruby script directly.
      if cl.path.end_with?("bundle")
        frame_count = 0
        break
      end
    end
    require_found ? 1 : frame_count - 1
  end

  def self.find_gem(path)
    if !path
      return
    elsif path.start_with?(ARCHDIR)
      n = path.delete_prefix(ARCHDIR).sub(DLEXT, "")
    elsif path.start_with?(LIBDIR)
      n = path.delete_prefix(LIBDIR).chomp(".rb")
    else
      return
    end
    (EXACT[n] || !!SINCE[n]) or PREFIXED[n = n[%r[\A[^/]+(?=/)]]] && n
  end

  def self.warning?(name, specs: nil)
    # name can be a feature name or a file path with String or Pathname
    feature = File.path(name)

    # The actual checks needed to properly identify the gem being required
    # are costly (see [Bug #20641]), so we first do a much cheaper check
    # to exclude the vast majority of candidates.
    if feature.include?("/")
      # If requiring $LIBDIR/mutex_m.rb, we check SINCE_FAST_PATH["mutex_m"]
      # We'll fail to warn requires for files that are not the entry point
      # of the gem, e.g. require "logger/formatter.rb" won't warn.
      # But that's acceptable because this warning is best effort,
      # and in the overwhelming majority of cases logger.rb will end
      # up required.
      return unless SINCE_FAST_PATH[File.basename(feature, ".*")]
    else
      return unless SINCE_FAST_PATH[feature]
    end

    # bootsnap expands `require "csv"` to `require "#{LIBDIR}/csv.rb"`,
    # and `require "syslog"` to `require "#{ARCHDIR}/syslog.so"`.
    name = feature.delete_prefix(ARCHDIR)
    name.delete_prefix!(LIBDIR)
    name.tr!("/", "-")
    name.sub!(LIBEXT, "")
    return if specs.include?(name)
    _t, path = $:.resolve_feature_path(feature)
    if gem = find_gem(path)
      return if specs.include?(gem)
      caller = caller_locations(3, 3)&.find {|c| c&.absolute_path}
      return if find_gem(caller&.absolute_path)
    elsif SINCE[name] && !path
      gem = true
    else
      return
    end

    return if WARNED[name]
    WARNED[name] = true
    if gem == true
      gem = name
      "#{feature} was loaded from the standard library, but"
    elsif gem
      return if WARNED[gem]
      WARNED[gem] = true
      "#{feature} is found in #{gem}, which"
    else
      return
    end + build_message(gem)
  end

  def self.build_message(gem)
    msg = " #{RUBY_VERSION < SINCE[gem] ? "will no longer be" : "is not"} part of the default gems starting from Ruby #{SINCE[gem]}."

    if defined?(Bundler)
      msg += "\nYou can add #{gem} to your Gemfile or gemspec to silence this warning."

      # We detect the gem name from caller_locations. First we walk until we find `require`
      # then take the first frame that's not from `require`.
      #
      # Additionally, we need to skip Bootsnap and Zeitwerk if present, these
      # gems decorate Kernel#require, so they are not really the ones issuing
      # the require call users should be warned about. Those are upwards.
      frames_to_skip = 3
      location = nil
      require_found = false
      Thread.each_caller_location do |cl|
        if frames_to_skip >= 1
          frames_to_skip -= 1
          next
        end

        if require_found
          if cl.base_label != "require"
            location = cl.path
            break
          end
        else
          if cl.base_label == "require"
            require_found = true
          end
        end
      end

      if location && File.file?(location) && !location.start_with?(Gem::BUNDLED_GEMS::LIBDIR)
        caller_gem = nil
        Gem.path.each do |path|
          if location =~ %r{#{path}/gems/([\w\-\.]+)}
            caller_gem = $1
            break
          end
        end
        if caller_gem
          msg += "\nAlso please contact the author of #{caller_gem} to request adding #{gem} into its gemspec."
        end
      end
    else
      msg += " Install #{gem} from RubyGems."
    end

    msg
  end

  freeze
end

# for RubyGems without Bundler environment.
# If loading library is not part of the default gems and the bundled gems, warn it.
class LoadError
  def message
    return super unless path

    name = path.tr("/", "-")
    if !defined?(Bundler) && Gem::BUNDLED_GEMS::SINCE[name] && !Gem::BUNDLED_GEMS::WARNED[name]
      warn name + Gem::BUNDLED_GEMS.build_message(name), uplevel: Gem::BUNDLED_GEMS.uplevel
    end
    super
  end
end

# :startdoc:
