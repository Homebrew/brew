# typed: strict
# frozen_string_literal: true

require "digest"
require "erb"
require "utils/github"
require "utils/output"

module Homebrew
  # Class for generating a formula from a template.
  class FormulaCreator
    include Utils::Output::Mixin

    sig { returns(String) }
    attr_accessor :name

    sig { returns(Version) }
    attr_reader :version

    sig { returns(String) }
    attr_reader :url

    sig { returns(T::Boolean) }
    attr_reader :head

    sig {
      params(url: String, name: T.nilable(String), version: T.nilable(String), tap: T.nilable(String),
             mode: T.nilable(Symbol), license: T.nilable(String), fetch: T::Boolean, head: T::Boolean).void
    }
    def initialize(url:, name: nil, version: nil, tap: nil, mode: nil, license: nil, fetch: false, head: false)
      @url = url
      @mode = mode
      @license = license
      @fetch = fetch

      tap = if tap.blank?
        CoreTap.instance
      else
        Tap.fetch(tap)
      end
      @tap = T.let(tap, Tap)

      if (match_github = url.match %r{github\.com/(?<user>[^/]+)/(?<repo>[^/]+).*})
        user = T.must(match_github[:user])
        repository = T.must(match_github[:repo])
        if repository.end_with?(".git")
          # e.g. https://github.com/Homebrew/brew.git
          repository.delete_suffix!(".git")
          head = true
        end
        odebug "github: #{user} #{repository} head:#{head}"
        if name.blank?
          name = repository
          odebug "name from github: #{name}"
        end
      elsif name.blank?
        stem = Pathname.new(url).stem
        name = if stem.start_with?("index.cgi") && stem.include?("=")
          # special cases first
          # gitweb URLs e.g. http://www.codesrc.com/gitweb/index.cgi?p=libzipper.git;a=summary
          stem.rpartition("=").last
        else
          # e.g. http://digit-labs.org/files/tools/synscan/releases/synscan-5.02.tar.gz
          pathver = Version.parse(stem).to_s
          stem.sub(/[-_.]?#{Regexp.escape(pathver)}$/, "")
        end
        odebug "name from url: #{name}"
      end
      @name = T.let(name, String)
      @head = head

      if version.present?
        version = Version.new(version)
        odebug "version from user: #{version}"
      else
        version = Version.detect(url)
        odebug "version from url: #{version}"
      end

      if fetch && user && repository
        github = GitHub.repository(user, repository)

        if version.null? && !head
          begin
            latest_release = GitHub.get_latest_release(user, repository)
            version = Version.new(latest_release.fetch("tag_name"))
            odebug "github: version from latest_release: #{version}"

            @url = "https://github.com/#{user}/#{repository}/archive/refs/tags/#{version}.tar.gz"
            odebug "github: url changed to source archive #{@url}"
          rescue GitHub::API::HTTPNotFoundError
            odebug "github: latest_release lookup failed: #{url}"
          end
        end
      end
      @github = T.let(github, T.untyped)
      @version = T.let(version, Version)

      @sha256 = T.let(nil, T.nilable(String))
      @desc = T.let(nil, T.nilable(String))
      @homepage = T.let(nil, T.nilable(String))
      @license = T.let(nil, T.nilable(String))
    end

    sig { void }
    def verify_tap_available!
      raise TapUnavailableError, @tap.name unless @tap.installed?
    end

    sig { returns(Pathname) }
    def write_formula!
      raise ArgumentError, "name is blank!" if @name.blank?
      raise ArgumentError, "tap is blank!" if @tap.blank?

      path = @tap.new_formula_path(@name)
      raise "#{path} already exists" if path.exist?

      if @version.nil? || @version.null?
        odie "Version cannot be determined from URL. Explicitly set the version with `--set-version` instead."
      end

      if @fetch
        unless @head
          r = Resource.new
          r.url(@url)
          r.owner = self
          filepath = r.fetch
          html_doctype_prefix = "<!doctype html"
          # Number of bytes to read from file start to ensure it is not HTML.
          # HTML may start with arbitrary number of whitespace lines.
          bytes_to_read = 100
          if File.read(filepath, bytes_to_read).strip.downcase.start_with?(html_doctype_prefix)
            raise "Downloaded URL is not archive"
          end

          @sha256 = T.let(filepath.sha256, T.nilable(String))
        end

        if @github
          @desc = @github["description"]
          @homepage = @github["homepage"].presence || "https://github.com/#{@github["full_name"]}"
          @license = @github["license"]["spdx_id"] if @github["license"]
        end
      end

      path.dirname.mkpath
      path.write ERB.new(template, trim_mode: ">").result(binding)
      path
    end

    private

    sig { params(name: String).returns(String) }
    def latest_versioned_formula(name)
      name_prefix = "#{name}@"
      CoreTap.instance.formula_names
             .select { |f| f.start_with?(name_prefix) }
             .max_by { |v| Gem::Version.new(v.sub(name_prefix, "")) } || "python"
    end

    sig { returns(String) }
    def template
      <<~ERB
        # Documentation: https://docs.brew.sh/Formula-Cookbook
        #                https://docs.brew.sh/rubydoc/Formula
        # PLEASE REMOVE ALL GENERATED COMMENTS BEFORE SUBMITTING YOUR PULL REQUEST!
        class #{Formulary.class_s(name)} < Formula
        <% if @mode == :python %>
          include Language::Python::Virtualenv

        <% end %>
          desc "#{@desc}"
          homepage "#{@homepage}"
        <% unless @head %>
          url "#{@url}"
        <% unless @version.detected_from_url? %>
          version "#{@version.to_s.delete_prefix("v")}"
        <% end %>
          sha256 "#{@sha256}"
        <% end %>
          license "#{@license}"
        <% if @head %>
          head "#{@url}"
        <% end %>

        <% if @mode == :cabal %>
          depends_on "cabal-install" => :build
          depends_on "ghc" => :build
        <% elsif @mode == :cmake %>
          depends_on "cmake" => :build
        <% elsif @mode == :crystal %>
          depends_on "crystal" => :build
        <% elsif @mode == :go %>
          depends_on "go" => :build
        <% elsif @mode == :meson %>
          depends_on "meson" => :build
          depends_on "ninja" => :build
        <% elsif @mode == :node %>
          depends_on "node"
        <% elsif @mode == :perl %>
          uses_from_macos "perl"
        <% elsif @mode == :python %>
          depends_on "#{latest_versioned_formula("python")}"
        <% elsif @mode == :ruby %>
          depends_on "ruby"
        <% elsif @mode == :rust %>
          depends_on "rust" => :build
        <% elsif @mode == :zig %>
          depends_on "zig" => :build
        <% elsif @mode.nil? %>
          # depends_on "cmake" => :build
        <% end %>

        <% if @mode == :perl || :python || :ruby %>
          # Additional dependency
          # resource "" do
          #   url ""
          #   sha256 ""
          # end

        <% end %>
          def install
        <% if @mode == :cabal %>
            system "cabal", "v2-update"
            system "cabal", "v2-install", *std_cabal_v2_args
        <% elsif @mode == :cmake %>
            system "cmake", "-S", ".", "-B", "build", *std_cmake_args
            system "cmake", "--build", "build"
            system "cmake", "--install", "build"
        <% elsif @mode == :autotools %>
            # Remove unrecognized options if they cause configure to fail
            # https://docs.brew.sh/rubydoc/Formula.html#std_configure_args-instance_method
            system "./configure", "--disable-silent-rules", *std_configure_args
            system "make", "install" # if this fails, try separate make/make install steps
        <% elsif @mode == :crystal %>
            system "shards", "build", "--release"
            bin.install "bin/#{name}"
        <% elsif @mode == :go %>
            system "go", "build", *std_go_args(ldflags: "-s -w")
        <% elsif @mode == :meson %>
            system "meson", "setup", "build", *std_meson_args
            system "meson", "compile", "-C", "build", "--verbose"
            system "meson", "install", "-C", "build"
        <% elsif @mode == :node %>
            system "npm", "install", *std_npm_args
            bin.install_symlink libexec.glob("bin/*")
        <% elsif @mode == :perl %>
            ENV.prepend_create_path "PERL5LIB", libexec/"lib/perl5"
            ENV.prepend_path "PERL5LIB", libexec/"lib"

            # Stage additional dependency (`Makefile.PL` style).
            # resource("").stage do
            #   system "perl", "Makefile.PL", "INSTALL_BASE=\#{libexec}"
            #   system "make"
            #   system "make", "install"
            # end

            # Stage additional dependency (`Build.PL` style).
            # resource("").stage do
            #   system "perl", "Build.PL", "--install_base", libexec
            #   system "./Build"
            #   system "./Build", "install"
            # end

            bin.install name
            bin.env_script_all_files(libexec/"bin", PERL5LIB: ENV["PERL5LIB"])
        <% elsif @mode == :python %>
            virtualenv_install_with_resources
        <% elsif @mode == :ruby %>
            ENV["BUNDLE_FORCE_RUBY_PLATFORM"] = "1"
            ENV["BUNDLE_WITHOUT"] = "development test"
            ENV["BUNDLE_VERSION"] = "system" # Avoid installing Bundler into the keg
            ENV["GEM_HOME"] = libexec

            system "bundle", "install"
            system "gem", "build", "\#{name}.gemspec"
            system "gem", "install", "\#{name}-\#{version}.gem"

            bin.install libexec/"bin/\#{name}"
            bin.env_script_all_files(libexec/"bin", GEM_HOME: ENV["GEM_HOME"])
        <% elsif @mode == :rust %>
            system "cargo", "install", *std_cargo_args
        <% elsif @mode == :zig %>
            system "zig", "build", *std_zig_args
        <% else %>
            # Remove unrecognized options if they cause configure to fail
            # https://docs.brew.sh/rubydoc/Formula.html#std_configure_args-instance_method
            system "./configure", "--disable-silent-rules", *std_configure_args
            # system "cmake", "-S", ".", "-B", "build", *std_cmake_args
        <% end %>
          end

          test do
            # `test do` will create, run in and delete a temporary directory.
            #
            # This test will fail and we won't accept that! For Homebrew/homebrew-core
            # this will need to be a test that verifies the functionality of the
            # software. Run the test with `brew test #{name}`. Options passed
            # to `brew install` such as `--HEAD` also need to be provided to `brew test`.
            #
            # The installed folder is not in the path, so use the entire path to any
            # executables being tested: `system bin/"program", "do", "something"`.
            system "false"
          end
        end
      ERB
    end
  end
end
