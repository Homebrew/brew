# frozen_string_literal: true

require_relative "rubygems_integration"
require_relative "source/git/git_proxy"

module Bundler
  class Env
    def self.write(io)
      io.write report
    end

    def self.report(options = {})
      print_gemfile = options.delete(:print_gemfile) { true }
      print_gemspecs = options.delete(:print_gemspecs) { true }

      out = String.new
      append_formatted_table("Environment", environment, out)
      append_formatted_table("Bundler Build Metadata", BuildMetadata.to_h, out)

      unless Bundler.settings.all.empty?
        out << "\n## Bundler settings\n\n```\n"
        Bundler.settings.all.each do |setting|
          out << setting << "\n"
          Bundler.settings.pretty_values_for(setting).each do |line|
            out << "  " << line << "\n"
          end
        end
        out << "```\n"
      end

      return out unless SharedHelpers.in_bundle?

      if print_gemfile
        gemfiles = [Bundler.default_gemfile]
        begin
          gemfiles = Bundler.definition.gemfiles
        rescue GemfileNotFound
          nil
        end

        out << "\n## Gemfile\n"
        gemfiles.each do |gemfile|
          out << "\n### #{SharedHelpers.relative_path_to(gemfile)}\n\n"
          out << "```ruby\n" << read_file(gemfile).chomp << "\n```\n"
        end

        out << "\n### #{SharedHelpers.relative_path_to(Bundler.default_lockfile)}\n\n"
        out << "```\n" << read_file(Bundler.default_lockfile).chomp << "\n```\n"
      end

      if print_gemspecs
        dsl = Dsl.new.tap {|d| d.eval_gemfile(Bundler.default_gemfile) }
        out << "\n## Gemspecs\n" unless dsl.gemspecs.empty?
        dsl.gemspecs.each do |gs|
          out << "\n### #{File.basename(gs.loaded_from)}"
          out << "\n\n```ruby\n" << read_file(gs.loaded_from).chomp << "\n```\n"
        end
      end

      out
    end

    def self.read_file(filename)
      Bundler.read_file(filename.to_s).strip
    rescue Errno::ENOENT
      "<No #{filename} found>"
    rescue RuntimeError => e
      "#{e.class}: #{e.message}"
    end

    def self.ruby_version
      "#{RUBY_VERSION}p#{RUBY_PATCHLEVEL} (#{RUBY_RELEASE_DATE} revision #{RUBY_REVISION}) [#{Gem::Platform.local}]"
    end

    def self.git_version
      Bundler::Source::Git::GitProxy.new(nil, nil).full_version
    rescue Bundler::Source::Git::GitNotInstalledError
      "not installed"
    end

    def self.version_of(script)
      return "not installed" unless Bundler.which(script)
      `#{script} --version`.chomp
    end

    def self.chruby_version
      return "not installed" unless Bundler.which("chruby-exec")
      `chruby-exec -- chruby --version`.
        sub(/.*^chruby: (#{Gem::Version::VERSION_PATTERN}).*/m, '\1')
    end

    def self.environment
      out = []

      out << ["Bundler", Bundler::VERSION]
      out << ["  Platforms", Gem.platforms.join(", ")]
      out << ["Ruby", ruby_version]
      out << ["  Full Path", Gem.ruby]
      out << ["  Config Dir", Pathname.new(Gem::ConfigFile::SYSTEM_WIDE_CONFIG_FILE).dirname]
      out << ["RubyGems", Gem::VERSION]
      out << ["  Gem Home", Gem.dir]
      out << ["  Gem Path", Gem.path.join(File::PATH_SEPARATOR)]
      out << ["  User Home", Gem.user_home]
      out << ["  User Path", Gem.user_dir]
      out << ["  Bin Dir", Gem.bindir]
      if defined?(OpenSSL::SSL)
        out << ["OpenSSL"]
        out << ["  Compiled", OpenSSL::OPENSSL_VERSION] if defined?(OpenSSL::OPENSSL_VERSION)
        out << ["  Loaded", OpenSSL::OPENSSL_LIBRARY_VERSION] if defined?(OpenSSL::OPENSSL_LIBRARY_VERSION)
        out << ["  Cert File", OpenSSL::X509::DEFAULT_CERT_FILE] if defined?(OpenSSL::X509::DEFAULT_CERT_FILE)
        out << ["  Cert Dir", OpenSSL::X509::DEFAULT_CERT_DIR] if defined?(OpenSSL::X509::DEFAULT_CERT_DIR)
      end
      out << ["Tools"]
      out << ["  Git", git_version]
      out << ["  RVM", ENV.fetch("rvm_version") { version_of("rvm") }]
      out << ["  rbenv", version_of("rbenv")]
      out << ["  chruby", chruby_version]

      %w[rubygems-bundler open_gem].each do |name|
        specs = Bundler.rubygems.find_name(name)
        out << ["  #{name}", "(#{specs.map(&:version).join(",")})"] unless specs.empty?
      end
      if (exe = caller_locations.last.absolute_path)&.match? %r{(exe|bin)/bundler?\z}
        shebang = File.read(exe).lines.first
        shebang.sub!(/^#!\s*/, "")
        unless shebang.start_with?(Gem.ruby, "/usr/bin/env ruby")
          out << ["Gem.ruby", Gem.ruby]
          out << ["bundle #!", shebang]
        end
      end

      out
    end

    def self.append_formatted_table(title, pairs, out)
      return if pairs.empty?
      out << "\n" unless out.empty?
      out << "## #{title}\n\n```\n"
      ljust = pairs.map {|k, _v| k.to_s.length }.max
      pairs.each do |k, v|
        out << "#{k.to_s.ljust(ljust)}  #{v}\n"
      end
      out << "```\n"
    end

    private_class_method :read_file, :ruby_version, :git_version, :append_formatted_table, :version_of, :chruby_version
  end
end
