# frozen_string_literal: true

require_relative "../command"

unless defined? Gem::Commands::GenerateIndexCommand
  class Gem::Commands::GenerateIndexCommand < Gem::Command
    module RubygemsTrampoline
      def description # :nodoc:
        <<~EOF
          The generate_index command has been moved to the rubygems-generate_index gem.
        EOF
      end

      def execute
        alert_error "Install the rubygems-generate_index gem for the generate_index command"
      end

      def invoke_with_build_args(args, build_args)
        name = "rubygems-generate_index"
        spec = begin
          Gem::Specification.find_by_name(name)
        rescue Gem::LoadError
          require "rubygems/dependency_installer"
          Gem.install(name, Gem::Requirement.default, Gem::DependencyInstaller::DEFAULT_OPTIONS).find {|s| s.name == name }
        end

        # remove the methods defined in this file so that the methods defined in the gem are used instead,
        # and without a method redefinition warning
        %w[description execute invoke_with_build_args].each do |method|
          RubygemsTrampoline.remove_method(method)
        end
        self.class.singleton_class.remove_method(:new)

        spec.activate
        Gem.load_plugin_files spec.matches_for_glob("rubygems_plugin#{Gem.suffix_pattern}")

        self.class.new.invoke_with_build_args(args, build_args)
      end
    end
    private_constant :RubygemsTrampoline

    # remove_method(:initialize) warns, but removing new does not warn
    def self.new
      command = allocate
      command.send(:initialize, "generate_index", "Generates the index files for a gem server directory (requires rubygems-generate_index)")
      command
    end

    prepend(RubygemsTrampoline)
  end
end
