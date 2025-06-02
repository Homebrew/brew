# frozen_string_literal: true

module Gem::BundlerVersionFinder
  def self.bundler_version
    v = ENV["BUNDLER_VERSION"]

    v ||= bundle_update_bundler_version
    return if v == true

    v ||= lockfile_version
    return unless v

    Gem::Version.new(v)
  end

  def self.prioritize!(specs)
    exact_match_index = specs.find_index {|spec| spec.version == bundler_version }
    return unless exact_match_index

    specs.unshift(specs.delete_at(exact_match_index))
  end

  def self.bundle_update_bundler_version
    return unless ["bundle", "bundler"].include? File.basename($0)
    return unless "update".start_with?(ARGV.first || " ")
    bundler_version = nil
    update_index = nil
    ARGV.each_with_index do |a, i|
      if update_index && update_index.succ == i && a =~ Gem::Version::ANCHORED_VERSION_PATTERN
        bundler_version = a
      end
      next unless a =~ /\A--bundler(?:[= ](#{Gem::Version::VERSION_PATTERN}))?\z/
      bundler_version = $1 || true
      update_index = i
    end
    bundler_version
  end
  private_class_method :bundle_update_bundler_version

  def self.lockfile_version
    return unless contents = lockfile_contents
    regexp = /\n\nBUNDLED WITH\n\s{2,}(#{Gem::Version::VERSION_PATTERN})\n/
    return unless contents =~ regexp
    $1
  end
  private_class_method :lockfile_version

  def self.lockfile_contents
    gemfile = ENV["BUNDLE_GEMFILE"]
    gemfile = nil if gemfile&.empty?

    unless gemfile
      begin
        Gem::Util.traverse_parents(Dir.pwd) do |directory|
          next unless gemfile = Gem::GEM_DEP_FILES.find {|f| File.file?(f) }

          gemfile = File.join directory, gemfile
          break
        end
      rescue Errno::ENOENT
        return
      end
    end

    return unless gemfile

    lockfile = case gemfile
               when "gems.rb" then "gems.locked"
               else "#{gemfile}.lock"
    end

    return unless File.file?(lockfile)

    File.read(lockfile)
  end
  private_class_method :lockfile_contents
end
