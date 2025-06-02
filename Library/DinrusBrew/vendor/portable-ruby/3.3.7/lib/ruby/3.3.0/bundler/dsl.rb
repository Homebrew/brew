# frozen_string_literal: true

require_relative "dependency"
require_relative "ruby_dsl"

module Bundler
  class Dsl
    include RubyDsl

    def self.evaluate(gemfile, lockfile, unlock)
      builder = new
      builder.eval_gemfile(gemfile)
      builder.to_definition(lockfile, unlock)
    end

    VALID_PLATFORMS = Bundler::Dependency::PLATFORM_MAP.keys.freeze

    VALID_KEYS = %w[group groups git path glob name branch ref tag require submodules
                    platform platforms type source install_if gemfile force_ruby_platform].freeze

    GITHUB_PULL_REQUEST_URL = %r{\Ahttps://github\.com/([A-Za-z0-9_\-\.]+/[A-Za-z0-9_\-\.]+)/pull/(\d+)\z}
    GITLAB_MERGE_REQUEST_URL = %r{\Ahttps://gitlab\.com/([A-Za-z0-9_\-\./]+)/-/merge_requests/(\d+)\z}

    attr_reader :gemspecs, :gemfile
    attr_accessor :dependencies

    def initialize
      @source               = nil
      @sources              = SourceList.new
      @git_sources          = {}
      @dependencies         = []
      @groups               = []
      @install_conditionals = []
      @optional_groups      = []
      @platforms            = []
      @env                  = nil
      @ruby_version         = nil
      @gemspecs             = []
      @gemfile              = nil
      @gemfiles             = []
      add_git_sources
    end

    def eval_gemfile(gemfile, contents = nil)
      with_gemfile(gemfile) do |current_gemfile|
        contents ||= Bundler.read_file(current_gemfile)
        instance_eval(contents, current_gemfile, 1)
      rescue GemfileEvalError => e
        message = "There was an error evaluating `#{File.basename current_gemfile}`: #{e.message}"
        raise DSLError.new(message, current_gemfile, e.backtrace, contents)
      rescue GemfileError, InvalidArgumentError, InvalidOption, DeprecatedError, ScriptError => e
        message = "There was an error parsing `#{File.basename current_gemfile}`: #{e.message}"
        raise DSLError.new(message, current_gemfile, e.backtrace, contents)
      rescue StandardError => e
        raise unless e.backtrace_locations.first.path == current_gemfile
        message = "There was an error parsing `#{File.basename current_gemfile}`: #{e.message}"
        raise DSLError.new(message, current_gemfile, e.backtrace, contents)
      end
    end

    def gemspec(opts = nil)
      opts ||= {}
      path              = opts[:path] || "."
      glob              = opts[:glob]
      name              = opts[:name]
      development_group = opts[:development_group] || :development
      expanded_path     = gemfile_root.join(path)

      gemspecs = Gem::Util.glob_files_in_dir("{,*}.gemspec", expanded_path).map {|g| Bundler.load_gemspec(g) }.compact
      gemspecs.reject! {|s| s.name != name } if name
      specs_by_name_and_version = gemspecs.group_by {|s| [s.name, s.version] }

      case specs_by_name_and_version.size
      when 1
        specs = specs_by_name_and_version.values.first
        spec = specs.find {|s| s.match_platform(Bundler.local_platform) } || specs.first

        @gemspecs << spec

        gem spec.name, name: spec.name, path: path, glob: glob

        group(development_group) do
          spec.development_dependencies.each do |dep|
            gem dep.name, *(dep.requirement.as_list + [type: :development])
          end
        end
      when 0
        raise InvalidOption, "There are no gemspecs at #{expanded_path}"
      else
        raise InvalidOption, "There are multiple gemspecs at #{expanded_path}. " \
          "Please use the :name option to specify which one should be used"
      end
    end

    def gem(name, *args)
      options = args.last.is_a?(Hash) ? args.pop.dup : {}
      options["gemfile"] = @gemfile
      version = args || [">= 0"]

      normalize_options(name, version, options)

      dep = Dependency.new(name, version, options)

      # if there's already a dependency with this name we try to prefer one
      if current = @dependencies.find {|d| d.name == dep.name }
        if current.requirement != dep.requirement
          current_requirement_open = current.requirements_list.include?(">= 0")

          gemspec_dep = [dep, current].find(&:gemspec_dev_dep?)
          if gemspec_dep
            gemfile_dep = [dep, current].find(&:runtime?)

            unless current_requirement_open
              Bundler.ui.warn "A gemspec development dependency (#{gemspec_dep.name}, #{gemspec_dep.requirement}) is being overridden by a Gemfile dependency (#{gemfile_dep.name}, #{gemfile_dep.requirement}).\n" \
                              "This behaviour may change in the future. Please remove either of them, or make sure they both have the same requirement\n"
            end
          else
            update_prompt = ""

            if File.basename(@gemfile) == Injector::INJECTED_GEMS
              if dep.requirements_list.include?(">= 0") && !current_requirement_open
                update_prompt = ". Gem already added"
              else
                update_prompt = ". If you want to update the gem version, run `bundle update #{current.name}`"

                update_prompt += ". You may also need to change the version requirement specified in the Gemfile if it's too restrictive." unless current_requirement_open
              end
            end

            raise GemfileError, "You cannot specify the same gem twice with different version requirements.\n" \
                           "You specified: #{current.name} (#{current.requirement}) and #{dep.name} (#{dep.requirement})" \
                           "#{update_prompt}"
          end
        end

        # Always prefer the dependency from the Gemfile
        if current.gemspec_dev_dep?
          @dependencies.delete(current)
        elsif dep.gemspec_dev_dep?
          return
        elsif current.source != dep.source
          raise GemfileError, "You cannot specify the same gem twice coming from different sources.\n" \
                          "You specified that #{dep.name} (#{dep.requirement}) should come from " \
                          "#{current.source || "an unspecified source"} and #{dep.source}\n"
        else
          Bundler.ui.warn "Your Gemfile lists the gem #{current.name} (#{current.requirement}) more than once.\n" \
                          "You should probably keep only one of them.\n" \
                          "Remove any duplicate entries and specify the gem only once.\n" \
                          "While it's not a problem now, it could cause errors if you change the version of one of them later."
        end
      end

      @dependencies << dep
    end

    def source(source, *args, &blk)
      options = args.last.is_a?(Hash) ? args.pop.dup : {}
      options = normalize_hash(options)
      source = normalize_source(source)

      if options.key?("type")
        options["type"] = options["type"].to_s
        unless Plugin.source?(options["type"])
          raise InvalidOption, "No plugin sources available for #{options["type"]}"
        end

        unless block_given?
          raise InvalidOption, "You need to pass a block to #source with :type option"
        end

        source_opts = options.merge("uri" => source)
        with_source(@sources.add_plugin_source(options["type"], source_opts), &blk)
      elsif block_given?
        with_source(@sources.add_rubygems_source("remotes" => source), &blk)
      else
        @sources.add_global_rubygems_remote(source)
      end
    end

    def git_source(name, &block)
      unless block_given?
        raise InvalidOption, "You need to pass a block to #git_source"
      end

      if valid_keys.include?(name.to_s)
        raise InvalidOption, "You cannot use #{name} as a git source. It " \
          "is a reserved key. Reserved keys are: #{valid_keys.join(", ")}"
      end

      @git_sources[name.to_s] = block
    end

    def path(path, options = {}, &blk)
      source_options = normalize_hash(options).merge(
        "path" => Pathname.new(path),
        "root_path" => gemfile_root,
        "gemspec" => gemspecs.find {|g| g.name == options["name"] }
      )

      source_options["global"] = true unless block_given?

      source = @sources.add_path_source(source_options)
      with_source(source, &blk)
    end

    def git(uri, options = {}, &blk)
      unless block_given?
        msg = "You can no longer specify a git source by itself. Instead, \n" \
              "either use the :git option on a gem, or specify the gems that \n" \
              "bundler should find in the git source by passing a block to \n" \
              "the git method, like: \n\n" \
              "  git 'git://github.com/rails/rails.git' do\n" \
              "    gem 'rails'\n" \
              "  end"
        raise DeprecatedError, msg
      end

      with_source(@sources.add_git_source(normalize_hash(options).merge("uri" => uri)), &blk)
    end

    def github(repo, options = {})
      raise InvalidArgumentError, "GitHub sources require a block" unless block_given?
      github_uri  = @git_sources["github"].call(repo)
      git_options = normalize_hash(options).merge("uri" => github_uri)
      git_source  = @sources.add_git_source(git_options)
      with_source(git_source) { yield }
    end

    def to_definition(lockfile, unlock)
      check_primary_source_safety
      Definition.new(lockfile, @dependencies, @sources, unlock, @ruby_version, @optional_groups, @gemfiles)
    end

    def group(*args, &blk)
      options = args.last.is_a?(Hash) ? args.pop.dup : {}
      normalize_group_options(options, args)

      @groups.concat args

      if options["optional"]
        optional_groups = args - @optional_groups
        @optional_groups.concat optional_groups
      end

      yield
    ensure
      args.each { @groups.pop }
    end

    def install_if(*args)
      @install_conditionals.concat args
      yield
    ensure
      args.each { @install_conditionals.pop }
    end

    def platforms(*platforms)
      @platforms.concat platforms
      yield
    ensure
      platforms.each { @platforms.pop }
    end
    alias_method :platform, :platforms

    def env(name)
      old = @env
      @env = name
      yield
    ensure
      @env = old
    end

    def plugin(*args)
      # Pass on
    end

    def method_missing(name, *args)
      raise GemfileError, "Undefined local variable or method `#{name}' for Gemfile"
    end

    def check_primary_source_safety
      check_path_source_safety
      check_rubygems_source_safety
    end

    private

    def with_gemfile(gemfile)
      expanded_gemfile_path = Pathname.new(gemfile).expand_path(@gemfile&.parent)
      original_gemfile = @gemfile
      @gemfile = expanded_gemfile_path
      @gemfiles << expanded_gemfile_path
      yield @gemfile.to_s
    ensure
      @gemfile = original_gemfile
    end

    def add_git_sources
      git_source(:github) do |repo_name|
        if repo_name =~ GITHUB_PULL_REQUEST_URL
          {
            "git" => "https://github.com/#{$1}.git",
            "branch" => nil,
            "ref" => "refs/pull/#{$2}/head",
            "tag" => nil,
          }
        else
          repo_name = "#{repo_name}/#{repo_name}" unless repo_name.include?("/")
          "https://github.com/#{repo_name}.git"
        end
      end

      git_source(:gist) do |repo_name|
        "https://gist.github.com/#{repo_name}.git"
      end

      git_source(:bitbucket) do |repo_name|
        user_name, repo_name = repo_name.split("/")
        repo_name ||= user_name
        "https://#{user_name}@bitbucket.org/#{user_name}/#{repo_name}.git"
      end

      git_source(:gitlab) do |repo_name|
        if repo_name =~ GITLAB_MERGE_REQUEST_URL
          {
            "git" => "https://gitlab.com/#{$1}.git",
            "branch" => nil,
            "ref" => "refs/merge-requests/#{$2}/head",
            "tag" => nil,
          }
        else
          repo_name = "#{repo_name}/#{repo_name}" unless repo_name.include?("/")
          "https://gitlab.com/#{repo_name}.git"
        end
      end
    end

    def with_source(source)
      old_source = @source
      if block_given?
        @source = source
        yield
      end
      source
    ensure
      @source = old_source
    end

    def normalize_hash(opts)
      opts.keys.each do |k|
        opts[k.to_s] = opts.delete(k) unless k.is_a?(String)
      end
      opts
    end

    def valid_keys
      @valid_keys ||= VALID_KEYS
    end

    def normalize_options(name, version, opts)
      if name.is_a?(Symbol)
        raise GemfileError, %(You need to specify gem names as Strings. Use 'gem "#{name}"' instead)
      end
      if /\s/.match?(name)
        raise GemfileError, %('#{name}' is not a valid gem name because it contains whitespace)
      end
      raise GemfileError, %(an empty gem name is not valid) if name.empty?

      normalize_hash(opts)

      git_names = @git_sources.keys.map(&:to_s)
      validate_keys("gem '#{name}'", opts, valid_keys + git_names)

      groups = @groups.dup
      opts["group"] = opts.delete("groups") || opts["group"]
      groups.concat Array(opts.delete("group"))
      groups = [:default] if groups.empty?

      install_if = @install_conditionals.dup
      install_if.concat Array(opts.delete("install_if"))
      install_if = install_if.reduce(true) do |memo, val|
        memo && (val.respond_to?(:call) ? val.call : val)
      end

      platforms = @platforms.dup
      opts["platforms"] = opts["platform"] || opts["platforms"]
      platforms.concat Array(opts.delete("platforms"))
      platforms.map!(&:to_sym)
      platforms.each do |p|
        next if VALID_PLATFORMS.include?(p)
        raise GemfileError, "`#{p}` is not a valid platform. The available options are: #{VALID_PLATFORMS.inspect}"
      end

      # Save sources passed in a key
      if opts.key?("source")
        source = normalize_source(opts["source"])
        opts["source"] = @sources.add_rubygems_source("remotes" => source)
      end

      git_name = (git_names & opts.keys).last
      if @git_sources[git_name]
        git_opts = @git_sources[git_name].call(opts[git_name])
        git_opts = { "git" => git_opts } if git_opts.is_a?(String)
        opts.merge!(git_opts) do |key, _gemfile_value, _git_source_value|
          raise GemfileError, %(The :#{key} option can't be used with `#{git_name}: #{opts[git_name].inspect}`)
        end
      end

      %w[git path].each do |type|
        next unless param = opts[type]
        if version.first && version.first =~ /^\s*=?\s*(\d[^\s]*)\s*$/
          options = opts.merge("name" => name, "version" => $1)
        else
          options = opts.dup
        end
        source = send(type, param, options) {}
        opts["source"] = source
      end

      opts["source"]         ||= @source
      opts["env"]            ||= @env
      opts["platforms"]      = platforms.dup
      opts["group"]          = groups
      opts["should_include"] = install_if
    end

    def normalize_group_options(opts, groups)
      normalize_hash(opts)

      groups = groups.map {|group| ":#{group}" }.join(", ")
      validate_keys("group #{groups}", opts, %w[optional])

      opts["optional"] ||= false
    end

    def validate_keys(command, opts, valid_keys)
      if opts["branch"] && !(opts["git"] || opts["github"] || (opts.keys & @git_sources.keys.map(&:to_s)).any?)
        raise GemfileError, %(The `branch` option for `#{command}` is not allowed. Only gems with a git source can specify a branch)
      end

      invalid_keys = opts.keys - valid_keys
      return true unless invalid_keys.any?

      message = String.new
      message << "You passed #{invalid_keys.map {|k| ":" + k }.join(", ")} "
      message << if invalid_keys.size > 1
        "as options for #{command}, but they are invalid."
      else
        "as an option for #{command}, but it is invalid."
      end

      message << " Valid options are: #{valid_keys.join(", ")}."
      message << " You may be able to resolve this by upgrading Bundler to the newest version."
      raise InvalidOption, message
    end

    def normalize_source(source)
      case source
      when :gemcutter, :rubygems, :rubyforge
        message =
          "The source :#{source} is deprecated because HTTP requests are insecure.\n" \
          "Please change your source to 'https://rubygems.org' if possible, or 'http://rubygems.org' if not."
        removed_message =
          "The source :#{source} is disallowed because HTTP requests are insecure.\n" \
          "Please change your source to 'https://rubygems.org' if possible, or 'http://rubygems.org' if not."
        Bundler::SharedHelpers.major_deprecation 2, message, removed_message: removed_message
        "http://rubygems.org"
      when String
        source
      else
        raise GemfileError, "Unknown source '#{source}'"
      end
    end

    def check_path_source_safety
      return if @sources.global_path_source.nil?

      msg = "You can no longer specify a path source by itself. Instead, \n" \
              "either use the :path option on a gem, or specify the gems that \n" \
              "bundler should find in the path source by passing a block to \n" \
              "the path method, like: \n\n" \
              "    path 'dir/containing/rails' do\n" \
              "      gem 'rails'\n" \
              "    end\n\n"

      SharedHelpers.major_deprecation(2, msg.strip)
    end

    def check_rubygems_source_safety
      if @sources.implicit_global_source?
        implicit_global_source_warning
      elsif @sources.aggregate_global_source?
        multiple_global_source_warning
      end
    end

    def implicit_global_source_warning
      Bundler::SharedHelpers.major_deprecation 2, "This Gemfile does not include an explicit global source. " \
        "Not using an explicit global source may result in a different lockfile being generated depending on " \
        "the gems you have installed locally before bundler is run. " \
        "Instead, define a global source in your Gemfile like this: source \"https://rubygems.org\"."
    end

    def multiple_global_source_warning
      if Bundler.feature_flag.bundler_3_mode?
        msg = "This Gemfile contains multiple global sources. " \
          "Each source after the first must include a block to indicate which gems " \
          "should come from that source"
        raise GemfileEvalError, msg
      else
        message =
          "Your Gemfile contains multiple global sources. " \
          "Using `source` more than once without a block is a security risk, and " \
          "may result in installing unexpected gems. To resolve this warning, use " \
          "a block to indicate which gems should come from the secondary source."
        removed_message =
          "Your Gemfile contains multiple global sources. " \
          "Using `source` more than once without a block is a security risk, and " \
          "may result in installing unexpected gems. To resolve this error, use " \
          "a block to indicate which gems should come from the secondary source."
        Bundler::SharedHelpers.major_deprecation 2, message, removed_message: removed_message
      end
    end

    class DSLError < GemfileError
      # @return [String] the description that should be presented to the user.
      #
      attr_reader :description

      # @return [String] the path of the dsl file that raised the exception.
      #
      attr_reader :dsl_path

      # @return [Exception] the backtrace of the exception raised by the
      #         evaluation of the dsl file.
      #
      attr_reader :backtrace

      # @param [Exception] backtrace @see backtrace
      # @param [String]    dsl_path  @see dsl_path
      #
      def initialize(description, dsl_path, backtrace, contents = nil)
        @status_code = $!.respond_to?(:status_code) && $!.status_code

        @description = description
        @dsl_path    = dsl_path
        @backtrace   = backtrace
        @contents    = contents
      end

      def status_code
        @status_code || super
      end

      # @return [String] the contents of the DSL that cause the exception to
      #         be raised.
      #
      def contents
        @contents ||= dsl_path && File.exist?(dsl_path) && File.read(dsl_path)
      end

      # The message of the exception reports the content of podspec for the
      # line that generated the original exception.
      #
      # @example Output
      #
      #   Invalid podspec at `RestKit.podspec` - undefined method
      #   `exclude_header_search_paths=' for #<Pod::Specification for
      #   `RestKit/Network (0.9.3)`>
      #
      #       from spec-repos/master/RestKit/0.9.3/RestKit.podspec:36
      #       -------------------------------------------
      #           # because it would break: #import <CoreData/CoreData.h>
      #    >      ns.exclude_header_search_paths = 'Code/RestKit.h'
      #         end
      #       -------------------------------------------
      #
      # @return [String] the message of the exception.
      #
      def to_s
        @to_s ||= begin
          trace_line, description = parse_line_number_from_description

          m = String.new("\n[!] ")
          m << description
          m << ". Bundler cannot continue.\n"

          return m unless backtrace && dsl_path && contents

          trace_line = backtrace.find {|l| l.include?(dsl_path) } || trace_line
          return m unless trace_line
          line_number = trace_line.split(":")[1].to_i - 1
          return m unless line_number

          lines      = contents.lines.to_a
          indent     = " #  "
          indicator  = indent.tr("#", ">")
          first_line = line_number.zero?
          last_line  = (line_number == (lines.count - 1))

          m << "\n"
          m << "#{indent}from #{trace_line.gsub(/:in.*$/, "")}\n"
          m << "#{indent}-------------------------------------------\n"
          m << "#{indent}#{lines[line_number - 1]}" unless first_line
          m << "#{indicator}#{lines[line_number]}"
          m << "#{indent}#{lines[line_number + 1]}" unless last_line
          m << "\n" unless m.end_with?("\n")
          m << "#{indent}-------------------------------------------\n"
        end
      end

      private

      def parse_line_number_from_description
        description = self.description
        if dsl_path && description =~ /((#{Regexp.quote File.expand_path(dsl_path)}|#{Regexp.quote dsl_path}):\d+)/
          trace_line = Regexp.last_match[1]
          description = description.sub(/\n.*\n(\.\.\.)? *\^~+$/, "").sub(/#{Regexp.quote trace_line}:\s*/, "").sub("\n", " - ")
        end
        [trace_line, description]
      end
    end

    def gemfile_root
      @gemfile ||= Bundler.default_gemfile
      @gemfile.dirname
    end
  end
end
