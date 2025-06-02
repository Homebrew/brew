# frozen_string_literal: true

require "pathname"

module Bundler
  class CLI
    Bundler.require_thor_actions
    include Thor::Actions
  end

  class CLI::Gem
    TEST_FRAMEWORK_VERSIONS = {
      "rspec" => "3.0",
      "minitest" => "5.16",
      "test-unit" => "3.0",
    }.freeze

    attr_reader :options, :gem_name, :thor, :name, :target, :extension

    def initialize(options, gem_name, thor)
      @options = options
      @gem_name = resolve_name(gem_name)

      @thor = thor
      thor.behavior = :invoke
      thor.destination_root = nil

      @name = @gem_name
      @target = SharedHelpers.pwd.join(gem_name)

      @extension = options[:ext]

      validate_ext_name if @extension
      validate_rust_builder_rubygems_version if @extension == "rust"
    end

    def run
      Bundler.ui.confirm "Creating gem '#{name}'..."

      underscored_name = name.tr("-", "_")
      namespaced_path = name.tr("-", "/")
      constant_name = name.gsub(/-[_-]*(?![_-]|$)/) { "::" }.gsub(/([_-]+|(::)|^)(.|$)/) { $2.to_s + $3.upcase }
      constant_array = constant_name.split("::")
      minitest_constant_name = constant_array.clone.tap {|a| a[-1] = "Test#{a[-1]}" }.join("::") # Foo::Bar => Foo::TestBar

      use_git = Bundler.git_present? && options[:git]

      git_author_name = use_git ? `git config user.name`.chomp : ""
      git_username = use_git ? `git config github.user`.chomp : ""
      git_user_email = use_git ? `git config user.email`.chomp : ""

      github_username = if options[:github_username].nil?
        git_username
      elsif options[:github_username] == false
        ""
      else
        options[:github_username]
      end

      config = {
        name: name,
        underscored_name: underscored_name,
        namespaced_path: namespaced_path,
        makefile_path: "#{underscored_name}/#{underscored_name}",
        constant_name: constant_name,
        constant_array: constant_array,
        author: git_author_name.empty? ? "TODO: Write your name" : git_author_name,
        email: git_user_email.empty? ? "TODO: Write your email address" : git_user_email,
        test: options[:test],
        ext: extension,
        exe: options[:exe],
        bundler_version: bundler_dependency_version,
        git: use_git,
        github_username: github_username.empty? ? "[USERNAME]" : github_username,
        required_ruby_version: required_ruby_version,
        rust_builder_required_rubygems_version: rust_builder_required_rubygems_version,
        minitest_constant_name: minitest_constant_name,
      }
      ensure_safe_gem_name(name, constant_array)

      templates = {
        "Gemfile.tt" => Bundler.preferred_gemfile_name,
        "lib/newgem.rb.tt" => "lib/#{namespaced_path}.rb",
        "lib/newgem/version.rb.tt" => "lib/#{namespaced_path}/version.rb",
        "sig/newgem.rbs.tt" => "sig/#{namespaced_path}.rbs",
        "newgem.gemspec.tt" => "#{name}.gemspec",
        "Rakefile.tt" => "Rakefile",
        "README.md.tt" => "README.md",
        "bin/console.tt" => "bin/console",
        "bin/setup.tt" => "bin/setup",
      }

      executables = %w[
        bin/console
        bin/setup
      ]

      templates.merge!("gitignore.tt" => ".gitignore") if use_git

      if test_framework = ask_and_set_test_framework
        config[:test] = test_framework
        config[:test_framework_version] = TEST_FRAMEWORK_VERSIONS[test_framework]

        case test_framework
        when "rspec"
          templates.merge!(
            "rspec.tt" => ".rspec",
            "spec/spec_helper.rb.tt" => "spec/spec_helper.rb",
            "spec/newgem_spec.rb.tt" => "spec/#{namespaced_path}_spec.rb"
          )
          config[:test_task] = :spec
        when "minitest"
          # Generate path for minitest target file (FileList["test/**/test_*.rb"])
          #   foo     => test/test_foo.rb
          #   foo-bar => test/foo/test_bar.rb
          #   foo_bar => test/test_foo_bar.rb
          paths = namespaced_path.rpartition("/")
          paths[2] = "test_#{paths[2]}"
          minitest_namespaced_path = paths.join("")

          templates.merge!(
            "test/minitest/test_helper.rb.tt" => "test/test_helper.rb",
            "test/minitest/test_newgem.rb.tt" => "test/#{minitest_namespaced_path}.rb"
          )
          config[:test_task] = :test
        when "test-unit"
          templates.merge!(
            "test/test-unit/test_helper.rb.tt" => "test/test_helper.rb",
            "test/test-unit/newgem_test.rb.tt" => "test/#{namespaced_path}_test.rb"
          )
          config[:test_task] = :test
        end
      end

      config[:ci] = ask_and_set_ci
      case config[:ci]
      when "github"
        templates.merge!("github/workflows/main.yml.tt" => ".github/workflows/main.yml")
        config[:ci_config_path] = ".github "
      when "gitlab"
        templates.merge!("gitlab-ci.yml.tt" => ".gitlab-ci.yml")
        config[:ci_config_path] = ".gitlab-ci.yml "
      when "circle"
        templates.merge!("circleci/config.yml.tt" => ".circleci/config.yml")
        config[:ci_config_path] = ".circleci "
      end

      if ask_and_set(:mit, "Do you want to license your code permissively under the MIT license?",
        "This means that any other developer or company will be legally allowed to use your code " \
        "for free as long as they admit you created it. You can read more about the MIT license " \
        "at https://choosealicense.com/licenses/mit.")
        config[:mit] = true
        Bundler.ui.info "MIT License enabled in config"
        templates.merge!("LICENSE.txt.tt" => "LICENSE.txt")
      end

      if ask_and_set(:coc, "Do you want to include a code of conduct in gems you generate?",
        "Codes of conduct can increase contributions to your project by contributors who " \
        "prefer collaborative, safe spaces. You can read more about the code of conduct at " \
        "contributor-covenant.org. Having a code of conduct means agreeing to the responsibility " \
        "of enforcing it, so be sure that you are prepared to do that. Be sure that your email " \
        "address is specified as a contact in the generated code of conduct so that people know " \
        "who to contact in case of a violation. For suggestions about " \
        "how to enforce codes of conduct, see https://bit.ly/coc-enforcement.")
        config[:coc] = true
        Bundler.ui.info "Code of conduct enabled in config"
        templates.merge!("CODE_OF_CONDUCT.md.tt" => "CODE_OF_CONDUCT.md")
      end

      if ask_and_set(:changelog, "Do you want to include a changelog?",
        "A changelog is a file which contains a curated, chronologically ordered list of notable " \
        "changes for each version of a project. To make it easier for users and contributors to" \
        " see precisely what notable changes have been made between each release (or version) of" \
        " the project. Whether consumers or developers, the end users of software are" \
        " human beings who care about what's in the software. When the software changes, people " \
        "want to know why and how. see https://keepachangelog.com")
        config[:changelog] = true
        Bundler.ui.info "Changelog enabled in config"
        templates.merge!("CHANGELOG.md.tt" => "CHANGELOG.md")
      end

      config[:linter] = ask_and_set_linter
      case config[:linter]
      when "rubocop"
        config[:linter_version] = rubocop_version
        Bundler.ui.info "RuboCop enabled in config"
        templates.merge!("rubocop.yml.tt" => ".rubocop.yml")
      when "standard"
        config[:linter_version] = standard_version
        Bundler.ui.info "Standard enabled in config"
        templates.merge!("standard.yml.tt" => ".standard.yml")
      end

      if config[:exe]
        templates.merge!("exe/newgem.tt" => "exe/#{name}")
        executables.push("exe/#{name}")
      end

      if extension == "c"
        templates.merge!(
          "ext/newgem/extconf-c.rb.tt" => "ext/#{name}/extconf.rb",
          "ext/newgem/newgem.h.tt" => "ext/#{name}/#{underscored_name}.h",
          "ext/newgem/newgem.c.tt" => "ext/#{name}/#{underscored_name}.c"
        )
      end

      if extension == "rust"
        templates.merge!(
          "Cargo.toml.tt" => "Cargo.toml",
          "ext/newgem/Cargo.toml.tt" => "ext/#{name}/Cargo.toml",
          "ext/newgem/extconf-rust.rb.tt" => "ext/#{name}/extconf.rb",
          "ext/newgem/src/lib.rs.tt" => "ext/#{name}/src/lib.rs",
        )
      end

      if target.exist? && !target.directory?
        Bundler.ui.error "Couldn't create a new gem named `#{gem_name}` because there's an existing file named `#{gem_name}`."
        exit Bundler::BundlerError.all_errors[Bundler::GenericSystemCallError]
      end

      if use_git
        Bundler.ui.info "Initializing git repo in #{target}"
        require "shellwords"
        `git init #{target.to_s.shellescape}`

        config[:git_default_branch] = File.read("#{target}/.git/HEAD").split("/").last.chomp
      end

      templates.each do |src, dst|
        destination = target.join(dst)
        thor.template("newgem/#{src}", destination, config)
      end

      executables.each do |file|
        path = target.join(file)
        executable = (path.stat.mode | 0o111)
        path.chmod(executable)
      end

      if use_git
        IO.popen(%w[git add .], { chdir: target }, &:read)
      end

      # Open gemspec in editor
      open_editor(options["edit"], target.join("#{name}.gemspec")) if options[:edit]

      Bundler.ui.info "Gem '#{name}' was successfully created. " \
        "For more information on making a RubyGem visit https://bundler.io/guides/creating_gem.html"
    end

    private

    def resolve_name(name)
      SharedHelpers.pwd.join(name).basename.to_s
    end

    def ask_and_set(key, header, message)
      choice = options[key]
      choice = Bundler.settings["gem.#{key}"] if choice.nil?

      if choice.nil?
        Bundler.ui.confirm header
        choice = Bundler.ui.yes? "#{message} y/(n):"
        Bundler.settings.set_global("gem.#{key}", choice)
      end

      choice
    end

    def validate_ext_name
      return unless gem_name.index("-")

      Bundler.ui.error "You have specified a gem name which does not conform to the \n" \
                       "naming guidelines for C extensions. For more information, \n" \
                       "see the 'Extension Naming' section at the following URL:\n" \
                       "https://guides.rubygems.org/gems-with-extensions/\n"
      exit 1
    end

    def ask_and_set_test_framework
      return if skip?(:test)
      test_framework = options[:test] || Bundler.settings["gem.test"]

      if test_framework.to_s.empty?
        Bundler.ui.confirm "Do you want to generate tests with your gem?"
        Bundler.ui.info hint_text("test")

        result = Bundler.ui.ask "Enter a test framework. rspec/minitest/test-unit/(none):"
        if /rspec|minitest|test-unit/.match?(result)
          test_framework = result
        else
          test_framework = false
        end
      end

      if Bundler.settings["gem.test"].nil?
        Bundler.settings.set_global("gem.test", test_framework)
      end

      if options[:test] == Bundler.settings["gem.test"]
        Bundler.ui.info "#{options[:test]} is already configured, ignoring --test flag."
      end

      test_framework
    end

    def skip?(option)
      options.key?(option) && options[option].nil?
    end

    def hint_text(setting)
      if Bundler.settings["gem.#{setting}"] == false
        "Your choice will only be applied to this gem."
      else
        "Future `bundle gem` calls will use your choice. " \
        "This setting can be changed anytime with `bundle config gem.#{setting}`."
      end
    end

    def ask_and_set_ci
      return if skip?(:ci)
      ci_template = options[:ci] || Bundler.settings["gem.ci"]

      if ci_template.to_s.empty?
        Bundler.ui.confirm "Do you want to set up continuous integration for your gem? " \
          "Supported services:\n" \
          "* CircleCI:       https://circleci.com/\n" \
          "* GitHub Actions: https://github.com/features/actions\n" \
          "* GitLab CI:      https://docs.gitlab.com/ee/ci/\n" \
          "\n"
        Bundler.ui.info hint_text("ci")

        result = Bundler.ui.ask "Enter a CI service. github/gitlab/circle/(none):"
        if /github|gitlab|circle/.match?(result)
          ci_template = result
        else
          ci_template = false
        end
      end

      if Bundler.settings["gem.ci"].nil?
        Bundler.settings.set_global("gem.ci", ci_template)
      end

      if options[:ci] == Bundler.settings["gem.ci"]
        Bundler.ui.info "#{options[:ci]} is already configured, ignoring --ci flag."
      end

      ci_template
    end

    def ask_and_set_linter
      return if skip?(:linter)
      linter_template = options[:linter] || Bundler.settings["gem.linter"]
      linter_template = deprecated_rubocop_option if linter_template.nil?

      if linter_template.to_s.empty?
        Bundler.ui.confirm "Do you want to add a code linter and formatter to your gem? " \
          "Supported Linters:\n" \
          "* RuboCop:       https://rubocop.org\n" \
          "* Standard:      https://github.com/standardrb/standard\n" \
          "\n"
        Bundler.ui.info hint_text("linter")

        result = Bundler.ui.ask "Enter a linter. rubocop/standard/(none):"
        if /rubocop|standard/.match?(result)
          linter_template = result
        else
          linter_template = false
        end
      end

      if Bundler.settings["gem.linter"].nil?
        Bundler.settings.set_global("gem.linter", linter_template)
      end

      # Once gem.linter safely set, unset the deprecated gem.rubocop
      unless Bundler.settings["gem.rubocop"].nil?
        Bundler.settings.set_global("gem.rubocop", nil)
      end

      if options[:linter] == Bundler.settings["gem.linter"]
        Bundler.ui.info "#{options[:linter]} is already configured, ignoring --linter flag."
      end

      linter_template
    end

    def deprecated_rubocop_option
      if !options[:rubocop].nil?
        if options[:rubocop]
          Bundler::SharedHelpers.major_deprecation 2,
            "--rubocop is deprecated, use --linter=rubocop",
            removed_message: "--rubocop has been removed, use --linter=rubocop"
          "rubocop"
        else
          Bundler::SharedHelpers.major_deprecation 2,
            "--no-rubocop is deprecated, use --linter",
            removed_message: "--no-rubocop has been removed, use --linter"
          false
        end
      elsif !Bundler.settings["gem.rubocop"].nil?
        Bundler::SharedHelpers.major_deprecation 2,
          "config gem.rubocop is deprecated; we've updated your config to use gem.linter instead",
          removed_message: "config gem.rubocop has been removed; we've updated your config to use gem.linter instead"
        Bundler.settings["gem.rubocop"] ? "rubocop" : false
      end
    end

    def bundler_dependency_version
      v = Gem::Version.new(Bundler::VERSION)
      req = v.segments[0..1]
      req << "a" if v.prerelease?
      req.join(".")
    end

    def ensure_safe_gem_name(name, constant_array)
      if /^\d/.match?(name)
        Bundler.ui.error "Invalid gem name #{name} Please give a name which does not start with numbers."
        exit 1
      end

      constant_name = constant_array.join("::")

      existing_constant = constant_array.inject(Object) do |c, s|
        defined = begin
          c.const_defined?(s)
        rescue NameError
          Bundler.ui.error "Invalid gem name #{name} -- `#{constant_name}` is an invalid constant name"
          exit 1
        end
        (defined && c.const_get(s)) || break
      end

      return unless existing_constant
      Bundler.ui.error "Invalid gem name #{name} constant #{constant_name} is already in use. Please choose another gem name."
      exit 1
    end

    def open_editor(editor, file)
      thor.run(%(#{editor} "#{file}"))
    end

    def rust_builder_required_rubygems_version
      "3.3.11"
    end

    def required_ruby_version
      "3.0.0"
    end

    def rubocop_version
      "1.21"
    end

    def standard_version
      "1.3"
    end

    def validate_rust_builder_rubygems_version
      if Gem::Version.new(rust_builder_required_rubygems_version) > Gem.rubygems_version
        Bundler.ui.error "Your RubyGems version (#{Gem.rubygems_version}) is too old to build Rust extension. Please update your RubyGems using `gem update --system` or any other way and try again."
        exit 1
      end
    end
  end
end
