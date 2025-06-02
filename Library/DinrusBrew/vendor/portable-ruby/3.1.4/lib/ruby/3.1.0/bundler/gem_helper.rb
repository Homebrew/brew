# frozen_string_literal: true

require_relative "../bundler"
require "shellwords"

module Bundler
  class GemHelper
    include Rake::DSL if defined? Rake::DSL

    class << self
      # set when install'd.
      attr_accessor :instance

      def install_tasks(opts = {})
        new(opts[:dir], opts[:name]).install
      end

      def tag_prefix=(prefix)
        instance.tag_prefix = prefix
      end

      def gemspec(&block)
        gemspec = instance.gemspec
        block.call(gemspec) if block
        gemspec
      end
    end

    attr_reader :spec_path, :base, :gemspec

    attr_writer :tag_prefix

    def initialize(base = nil, name = nil)
      @base = File.expand_path(base || SharedHelpers.pwd)
      gemspecs = name ? [File.join(@base, "#{name}.gemspec")] : Gem::Util.glob_files_in_dir("{,*}.gemspec", @base)
      raise "Unable to determine name from existing gemspec. Use :name => 'gemname' in #install_tasks to manually set it." unless gemspecs.size == 1
      @spec_path = gemspecs.first
      @gemspec = Bundler.load_gemspec(@spec_path)
      @tag_prefix = ""
    end

    def install
      built_gem_path = nil

      desc "Build #{name}-#{version}.gem into the pkg directory."
      task "build" do
        built_gem_path = build_gem
      end

      desc "Generate SHA512 checksum if #{name}-#{version}.gem into the checksums directory."
      task "build:checksum" => "build" do
        build_checksum(built_gem_path)
      end

      desc "Build and install #{name}-#{version}.gem into system gems."
      task "install" => "build" do
        install_gem(built_gem_path)
      end

      desc "Build and install #{name}-#{version}.gem into system gems without network access."
      task "install:local" => "build" do
        install_gem(built_gem_path, :local)
      end

      desc "Create tag #{version_tag} and build and push #{name}-#{version}.gem to #{gem_push_host}\n" \
           "To prevent publishing in RubyGems use `gem_push=no rake release`"
      task "release", [:remote] => ["build", "release:guard_clean",
                                    "release:source_control_push", "release:rubygem_push"] do
      end

      task "release:guard_clean" do
        guard_clean
      end

      task "release:source_control_push", [:remote] do |_, args|
        tag_version { git_push(args[:remote]) } unless already_tagged?
      end

      task "release:rubygem_push" => "build" do
        rubygem_push(built_gem_path) if gem_push?
      end

      GemHelper.instance = self
    end

    def build_gem
      file_name = nil
      sh([*gem_command, "build", "-V", spec_path]) do
        file_name = File.basename(built_gem_path)
        SharedHelpers.filesystem_access(File.join(base, "pkg")) {|p| FileUtils.mkdir_p(p) }
        FileUtils.mv(built_gem_path, "pkg")
        Bundler.ui.confirm "#{name} #{version} built to pkg/#{file_name}."
      end
      File.join(base, "pkg", file_name)
    end

    def install_gem(built_gem_path = nil, local = false)
      built_gem_path ||= build_gem
      cmd = [*gem_command, "install", built_gem_path.to_s]
      cmd << "--local" if local
      sh(cmd)
      Bundler.ui.confirm "#{name} (#{version}) installed."
    end

    def build_checksum(built_gem_path = nil)
      built_gem_path ||= build_gem
      SharedHelpers.filesystem_access(File.join(base, "checksums")) {|p| FileUtils.mkdir_p(p) }
      file_name = "#{File.basename(built_gem_path)}.sha512"
      require "digest/sha2"
      checksum = ::Digest::SHA512.file(built_gem_path).hexdigest
      target = File.join(base, "checksums", file_name)
      File.write(target, checksum + "\n")
      Bundler.ui.confirm "#{name} #{version} checksum written to checksums/#{file_name}."
    end

    protected

    def rubygem_push(path)
      cmd = [*gem_command, "push", path]
      cmd << "--key" << gem_key if gem_key
      cmd << "--host" << allowed_push_host if allowed_push_host
      sh_with_input(cmd)
      Bundler.ui.confirm "Pushed #{name} #{version} to #{gem_push_host}"
    end

    def built_gem_path
      Gem::Util.glob_files_in_dir("#{name}-*.gem", base).sort_by {|f| File.mtime(f) }.last
    end

    def git_push(remote = nil)
      remote ||= default_remote
      sh("git push #{remote} refs/heads/#{current_branch}".shellsplit)
      sh("git push #{remote} refs/tags/#{version_tag}".shellsplit)
      Bundler.ui.confirm "Pushed git commits and release tag."
    end

    def default_remote
      remote_for_branch, status = sh_with_status(%W[git config --get branch.#{current_branch}.remote])
      return "origin" unless status.success?

      remote_for_branch.strip
    end

    def current_branch
      # We can replace this with `git branch --show-current` once we drop support for git < 2.22.0
      sh(%w[git rev-parse --abbrev-ref HEAD]).gsub(%r{\Aheads/}, "").strip
    end

    def allowed_push_host
      @gemspec.metadata["allowed_push_host"] if @gemspec.respond_to?(:metadata)
    end

    def gem_push_host
      env_rubygems_host = ENV["RUBYGEMS_HOST"]
      env_rubygems_host = nil if
        env_rubygems_host && env_rubygems_host.empty?

      allowed_push_host || env_rubygems_host || "rubygems.org"
    end

    def already_tagged?
      return false unless sh(%w[git tag]).split(/\n/).include?(version_tag)
      Bundler.ui.confirm "Tag #{version_tag} has already been created."
      true
    end

    def guard_clean
      clean? && committed? || raise("There are files that need to be committed first.")
    end

    def clean?
      sh_with_status(%w[git diff --exit-code])[1].success?
    end

    def committed?
      sh_with_status(%w[git diff-index --quiet --cached HEAD])[1].success?
    end

    def tag_version
      sh %W[git tag -m Version\ #{version} #{version_tag}]
      Bundler.ui.confirm "Tagged #{version_tag}."
      yield if block_given?
    rescue RuntimeError
      Bundler.ui.error "Untagging #{version_tag} due to error."
      sh_with_status %W[git tag -d #{version_tag}]
      raise
    end

    def version
      gemspec.version
    end

    def version_tag
      "#{@tag_prefix}v#{version}"
    end

    def name
      gemspec.name
    end

    def sh_with_input(cmd)
      Bundler.ui.debug(cmd)
      SharedHelpers.chdir(base) do
        abort unless Kernel.system(*cmd)
      end
    end

    def sh(cmd, &block)
      out, status = sh_with_status(cmd, &block)
      unless status.success?
        raise("Running `#{cmd.shelljoin}` failed with the following output:\n\n#{out}\n")
      end
      out
    end

    def sh_with_status(cmd, &block)
      Bundler.ui.debug(cmd)
      SharedHelpers.chdir(base) do
        outbuf = IO.popen(cmd, :err => [:child, :out], &:read)
        status = $?
        block.call(outbuf) if status.success? && block
        [outbuf, status]
      end
    end

    def gem_key
      Bundler.settings["gem.push_key"].to_s.downcase if Bundler.settings["gem.push_key"]
    end

    def gem_push?
      !%w[n no nil false off 0].include?(ENV["gem_push"].to_s.downcase)
    end

    def gem_command
      ENV["GEM_COMMAND"]&.shellsplit || ["gem"]
    end
  end
end
