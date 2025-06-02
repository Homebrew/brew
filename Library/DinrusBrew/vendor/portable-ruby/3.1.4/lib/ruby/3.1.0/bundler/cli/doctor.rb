# frozen_string_literal: true

require "rbconfig"
require "shellwords"
require "fiddle"

module Bundler
  class CLI::Doctor
    DARWIN_REGEX = /\s+(.+) \(compatibility /.freeze
    LDD_REGEX = /\t\S+ => (\S+) \(\S+\)/.freeze

    attr_reader :options

    def initialize(options)
      @options = options
    end

    def otool_available?
      Bundler.which("otool")
    end

    def ldd_available?
      Bundler.which("ldd")
    end

    def dylibs_darwin(path)
      output = `/usr/bin/otool -L #{path.shellescape}`.chomp
      dylibs = output.split("\n")[1..-1].map {|l| l.match(DARWIN_REGEX).captures[0] }.uniq
      # ignore @rpath and friends
      dylibs.reject {|dylib| dylib.start_with? "@" }
    end

    def dylibs_ldd(path)
      output = `/usr/bin/ldd #{path.shellescape}`.chomp
      output.split("\n").map do |l|
        match = l.match(LDD_REGEX)
        next if match.nil?
        match.captures[0]
      end.compact
    end

    def dylibs(path)
      case RbConfig::CONFIG["host_os"]
      when /darwin/
        return [] unless otool_available?
        dylibs_darwin(path)
      when /(linux|solaris|bsd)/
        return [] unless ldd_available?
        dylibs_ldd(path)
      else # Windows, etc.
        Bundler.ui.warn("Dynamic library check not supported on this platform.")
        []
      end
    end

    def bundles_for_gem(spec)
      Dir.glob("#{spec.full_gem_path}/**/*.bundle")
    end

    def check!
      require_relative "check"
      Bundler::CLI::Check.new({}).run
    end

    def run
      Bundler.ui.level = "warn" if options[:quiet]
      Bundler.settings.validate!
      check!

      definition = Bundler.definition
      broken_links = {}

      definition.specs.each do |spec|
        bundles_for_gem(spec).each do |bundle|
          bad_paths = dylibs(bundle).select do |f|
            begin
              Fiddle.dlopen(f)
              false
            rescue Fiddle::DLError
              true
            end
          end
          if bad_paths.any?
            broken_links[spec] ||= []
            broken_links[spec].concat(bad_paths)
          end
        end
      end

      permissions_valid = check_home_permissions

      if broken_links.any?
        message = "The following gems are missing OS dependencies:"
        broken_links.map do |spec, paths|
          paths.uniq.map do |path|
            "\n * #{spec.name}: #{path}"
          end
        end.flatten.sort.each {|m| message += m }
        raise ProductionError, message
      elsif !permissions_valid
        Bundler.ui.info "No issues found with the installed bundle"
      end
    end

    private

    def check_home_permissions
      require "find"
      files_not_readable_or_writable = []
      files_not_rw_and_owned_by_different_user = []
      files_not_owned_by_current_user_but_still_rw = []
      broken_symlinks = []
      Find.find(Bundler.bundle_path.to_s).each do |f|
        if !File.exist?(f)
          broken_symlinks << f
        elsif !File.writable?(f) || !File.readable?(f)
          if File.stat(f).uid != Process.uid
            files_not_rw_and_owned_by_different_user << f
          else
            files_not_readable_or_writable << f
          end
        elsif File.stat(f).uid != Process.uid
          files_not_owned_by_current_user_but_still_rw << f
        end
      end

      ok = true

      if broken_symlinks.any?
        Bundler.ui.warn "Broken links exist in the Bundler home. Please report them to the offending gem's upstream repo. These files are:\n - #{broken_symlinks.join("\n - ")}"

        ok = false
      end

      if files_not_owned_by_current_user_but_still_rw.any?
        Bundler.ui.warn "Files exist in the Bundler home that are owned by another " \
          "user, but are still readable/writable. These files are:\n - #{files_not_owned_by_current_user_but_still_rw.join("\n - ")}"

        ok = false
      end

      if files_not_rw_and_owned_by_different_user.any?
        Bundler.ui.warn "Files exist in the Bundler home that are owned by another " \
          "user, and are not readable/writable. These files are:\n - #{files_not_rw_and_owned_by_different_user.join("\n - ")}"

        ok = false
      end

      if files_not_readable_or_writable.any?
        Bundler.ui.warn "Files exist in the Bundler home that are not " \
          "readable/writable by the current user. These files are:\n - #{files_not_readable_or_writable.join("\n - ")}"

        ok = false
      end

      ok
    end
  end
end
