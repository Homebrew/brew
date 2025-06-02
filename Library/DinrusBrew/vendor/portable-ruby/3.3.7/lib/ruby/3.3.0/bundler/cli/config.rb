# frozen_string_literal: true

module Bundler
  class CLI::Config < Thor
    class_option :parseable, type: :boolean, banner: "Use minimal formatting for more parseable output"

    def self.scope_options
      method_option :global, type: :boolean, banner: "Only change the global config"
      method_option :local, type: :boolean, banner: "Only change the local config"
    end
    private_class_method :scope_options

    desc "base NAME [VALUE]", "The Bundler 1 config interface", hide: true
    scope_options
    method_option :delete, type: :boolean, banner: "delete"
    def base(name = nil, *value)
      new_args =
        if ARGV.size == 1
          ["config", "list"]
        elsif ARGV.include?("--delete")
          ARGV.map {|arg| arg == "--delete" ? "unset" : arg }
        elsif ARGV.include?("--global") || ARGV.include?("--local") || ARGV.size == 3
          ["config", "set", *ARGV[1..-1]]
        else
          ["config", "get", ARGV[1]]
        end

      message = "Using the `config` command without a subcommand [list, get, set, unset] is deprecated and will be removed in the future. Use `bundle #{new_args.join(" ")}` instead."
      removed_message = "Using the `config` command without a subcommand [list, get, set, unset] is has been removed. Use `bundle #{new_args.join(" ")}` instead."
      SharedHelpers.major_deprecation 3, message, removed_message: removed_message

      Base.new(options, name, value, self).run
    end

    desc "list", "List out all configured settings"
    def list
      Base.new(options, nil, nil, self).run
    end

    desc "get NAME", "Returns the value for the given key"
    def get(name)
      Base.new(options, name, nil, self).run
    end

    desc "set NAME VALUE", "Sets the given value for the given key"
    scope_options
    def set(name, value, *value_)
      Base.new(options, name, value_.unshift(value), self).run
    end

    desc "unset NAME", "Unsets the value for the given key"
    scope_options
    def unset(name)
      options[:delete] = true
      Base.new(options, name, nil, self).run
    end

    default_task :base

    class Base
      attr_reader :name, :value, :options, :scope, :thor

      def initialize(options, name, value, thor)
        @options = options
        @name = name
        value = Array(value)
        @value = value.empty? ? nil : value.join(" ")
        @thor = thor
        validate_scope!
      end

      def run
        unless name
          warn_unused_scope "Ignoring --#{scope}"
          confirm_all
          return
        end

        if options[:delete]
          if !explicit_scope? || scope != "global"
            Bundler.settings.set_local(name, nil)
          end
          if !explicit_scope? || scope != "local"
            Bundler.settings.set_global(name, nil)
          end
          return
        end

        if value.nil?
          warn_unused_scope "Ignoring --#{scope} since no value to set was given"

          if options[:parseable]
            if value = Bundler.settings[name]
              Bundler.ui.info("#{name}=#{value}")
            end
            return
          end

          confirm(name)
          return
        end

        Bundler.ui.info(message) if message
        Bundler.settings.send("set_#{scope}", name, new_value)
      end

      def confirm_all
        if @options[:parseable]
          thor.with_padding do
            Bundler.settings.all.each do |setting|
              val = Bundler.settings[setting]
              Bundler.ui.info "#{setting}=#{val}"
            end
          end
        else
          Bundler.ui.confirm "Settings are listed in order of priority. The top value will be used.\n"
          Bundler.settings.all.each do |setting|
            Bundler.ui.confirm setting
            show_pretty_values_for(setting)
            Bundler.ui.confirm ""
          end
        end
      end

      def confirm(name)
        Bundler.ui.confirm "Settings for `#{name}` in order of priority. The top value will be used"
        show_pretty_values_for(name)
      end

      def new_value
        pathname = Pathname.new(value)
        if name.start_with?("local.") && pathname.directory?
          pathname.expand_path.to_s
        else
          value
        end
      end

      def message
        locations = Bundler.settings.locations(name)
        if @options[:parseable]
          "#{name}=#{new_value}" if new_value
        elsif scope == "global"
          if !locations[:local].nil?
            "Your application has set #{name} to #{locations[:local].inspect}. " \
              "This will override the global value you are currently setting"
          elsif locations[:env]
            "You have a bundler environment variable for #{name} set to " \
              "#{locations[:env].inspect}. This will take precedence over the global value you are setting"
          elsif !locations[:global].nil? && locations[:global] != value
            "You are replacing the current global value of #{name}, which is currently " \
              "#{locations[:global].inspect}"
          end
        elsif scope == "local" && !locations[:local].nil? && locations[:local] != value
          "You are replacing the current local value of #{name}, which is currently " \
            "#{locations[:local].inspect}"
        end
      end

      def show_pretty_values_for(setting)
        thor.with_padding do
          Bundler.settings.pretty_values_for(setting).each do |line|
            Bundler.ui.info line
          end
        end
      end

      def explicit_scope?
        @explicit_scope
      end

      def warn_unused_scope(msg)
        return unless explicit_scope?
        return if options[:parseable]

        Bundler.ui.warn(msg)
      end

      def validate_scope!
        @explicit_scope = true
        scopes = %w[global local].select {|s| options[s] }
        case scopes.size
        when 0
          @scope = inside_app? ? "local" : "global"
          @explicit_scope = false
        when 1
          @scope = scopes.first
        else
          raise InvalidOption,
            "The options #{scopes.join " and "} were specified. Please only use one of the switches at a time."
        end
      end

      private

      def inside_app?
        Bundler.root
        true
      rescue GemfileNotFound
        false
      end
    end
  end
end
