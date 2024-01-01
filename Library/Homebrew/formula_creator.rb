# typed: true
# frozen_string_literal: true

require "digest"
require "erb"

module Homebrew
  # Class for generating a formula from a template.
  #
  # @api private
  class FormulaCreator
    attr_accessor :name

    sig {
      params(name: T.nilable(String), version: T.nilable(String), tap: T.nilable(String), url: String,
             mode: T.nilable(Symbol), license: T.nilable(String), fetch: T::Boolean, head: T::Boolean).void
    }
    def initialize(name, version, tap:, url:, mode:, license:, fetch:, head:)
      @name = name
      @version = Version.new(version) if version
      @tap = Tap.fetch(tap || "homebrew/core")
      @url = url
      @mode = mode
      @license = license
      @fetch = fetch
      @head = head
    end

    sig { void }
    def verify
      raise TapUnavailableError, @tap.name unless @tap.installed?
    end

    def self.name_from_url(url)
      stem = Pathname.new(url).stem
      # special cases first
      if stem.start_with? "index.cgi"
        # gitweb URLs e.g. http://www.codesrc.com/gitweb/index.cgi?p=libzipper.git;a=summary
        stem.rpartition("=").last
      elsif url =~ %r{github\.com/\S+/(\S+)/(archive|releases)/}
        # e.g. https://github.com/stella-emu/stella/releases/download/6.7/stella-6.7-src.tar.xz
        Regexp.last_match(1)
      else
        # e.g. http://digit-labs.org/files/tools/synscan/releases/synscan-5.02.tar.gz
        pathver = Version.parse(stem).to_s
        stem.sub(/[-_.]?#{Regexp.escape(pathver)}$/, "")
      end
    end

    def parse_url
      @name = FormulaCreator.name_from_url(@url) if @name.blank?
      odebug "name_from_url: #{@name}"
      @version = Version.detect(@url) if @version.nil?

      case @url
      when %r{github\.com/(\S+)/(\S+)\.git}
        @user = Regexp.last_match(1)
        @head = true
        @github = true
      when %r{github\.com/(\S+)/(\S+)/(archive|releases)/}
        @user = Regexp.last_match(1)
        @github = true
      end
    end

    def write_formula!
      raise ArgumentError, "name is blank!" if @name.blank?
      raise ArgumentError, "tap is blank!" if @tap.blank?

      path = @tap.new_formula_path(@name)
      raise "#{path} already exists" if path.exist?

      if @version.nil? || @version.null?
        odie "Version cannot be determined from URL. Explicitly set the version with `--set-version` instead."
      elsif @fetch
        unless @head
          r = Resource.new
          r.url(@url)
          r.version(@version)
          r.owner = self
          @sha256 = r.fetch.sha256 if r.download_strategy == CurlDownloadStrategy
        end

        if @user && @name
          begin
            metadata = GitHub.repository(@user, @name)
            @desc = metadata["description"]
            @homepage = metadata["homepage"]
            @license = metadata["license"]["spdx_id"] if metadata["license"]
          rescue GitHub::API::HTTPNotFoundError
            # If there was no repository found assume the network connection is at
            # fault rather than the input URL.
            nil
          end
        end
      end

      path.dirname.mkpath
      path.write ERB.new(template, trim_mode: ">").result(binding)
      path
    end

    sig { returns(String) }
    def template
      <<~ERB
        # Documentation: https://docs.brew.sh/Formula-Cookbook
        #                https://rubydoc.brew.sh/Formula
        # PLEASE REMOVE ALL GENERATED COMMENTS BEFORE SUBMITTING YOUR PULL REQUEST!
        <% if @mode == :node %>
        require "language/node"

        <% end %>
        class #{Formulary.class_s(name)} < Formula
        <% if @mode == :python %>
          include Language::Python::Virtualenv

        <% end %>
          desc "#{@desc}"
          homepage "#{@homepage}"
        <% unless @head %>
          url "#{@url}"
        <% unless @version.detected_from_url? %>
          version "#{@version}"
        <% end %>
          sha256 "#{@sha256}"
        <% end %>
          license "#{@license}"
        <% if @head %>
          head "#{@url}"
        <% end %>

        <% if @mode == :cmake %>
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
          depends_on "python"
        <% elsif @mode == :ruby %>
          uses_from_macos "ruby"
        <% elsif @mode == :rust %>
          depends_on "rust" => :build
        <% elsif @mode.nil? %>
          # depends_on "cmake" => :build
        <% end %>

        <% if @mode == :perl %>
          # Additional dependency
          # resource "" do
          #   url ""
          #   sha256 ""
          # end

        <% end %>
          def install
            # ENV.deparallelize  # if your formula fails when building in parallel
        <% if @mode == :cmake %>
            system "cmake", "-S", ".", "-B", "build", *std_cmake_args
            system "cmake", "--build", "build"
            system "cmake", "--install", "build"
        <% elsif @mode == :autotools %>
            # Remove unrecognized options if they cause configure to fail
            # https://rubydoc.brew.sh/Formula.html#std_configure_args-instance_method
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
            system "npm", "install", *Language::Node.std_npm_install_args(libexec)
            bin.install_symlink Dir["\#{libexec}/bin/*"]
        <% elsif @mode == :perl %>
            ENV.prepend_create_path "PERL5LIB", libexec/"lib/perl5"
            ENV.prepend_path "PERL5LIB", libexec/"lib"

            # Stage additional dependency (Makefile.PL style)
            # resource("").stage do
            #   system "perl", "Makefile.PL", "INSTALL_BASE=\#{libexec}"
            #   system "make"
            #   system "make", "install"
            # end

            # Stage additional dependency (Build.PL style)
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
            ENV["GEM_HOME"] = libexec
            system "gem", "build", "\#{name}.gemspec"
            system "gem", "install", "\#{name}-\#{@version}.gem"
            bin.install libexec/"bin/\#{name}"
            bin.env_script_all_files(libexec/"bin", GEM_HOME: ENV["GEM_HOME"])
        <% elsif @mode == :rust %>
            system "cargo", "install", *std_cargo_args
        <% else %>
            # Remove unrecognized options if they cause configure to fail
            # https://rubydoc.brew.sh/Formula.html#std_configure_args-instance_method
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
            # executables being tested: `system "\#{bin}/program", "do", "something"`.
            system "false"
          end
        end
      ERB
    end
  end
end
