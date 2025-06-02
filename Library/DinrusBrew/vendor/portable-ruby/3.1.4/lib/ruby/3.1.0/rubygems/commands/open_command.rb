# frozen_string_literal: true
require_relative "../command"
require_relative "../version_option"

class Gem::Commands::OpenCommand < Gem::Command
  include Gem::VersionOption

  def initialize
    super "open", "Open gem sources in editor"

    add_option("-e", "--editor COMMAND", String,
               "Prepends COMMAND to gem path. Could be used to specify editor.") do |command, options|
      options[:editor] = command || get_env_editor
    end
    add_option("-v", "--version VERSION", String,
               "Opens specific gem version") do |version|
      options[:version] = version
    end
  end

  def arguments # :nodoc:
    "GEMNAME     name of gem to open in editor"
  end

  def defaults_str # :nodoc:
    "-e #{get_env_editor}"
  end

  def description # :nodoc:
    <<-EOF
        The open command opens gem in editor and changes current path
        to gem's source directory.
        Editor command can be specified with -e option, otherwise rubygems
        will look for editor in $EDITOR, $VISUAL and $GEM_EDITOR variables.
    EOF
  end

  def usage # :nodoc:
    "#{program_name} [-e COMMAND] GEMNAME"
  end

  def get_env_editor
    ENV["GEM_EDITOR"] ||
      ENV["VISUAL"] ||
      ENV["EDITOR"] ||
      "vi"
  end

  def execute
    @version = options[:version] || Gem::Requirement.default
    @editor  = options[:editor] || get_env_editor

    found = open_gem(get_one_gem_name)

    terminate_interaction 1 unless found
  end

  def open_gem(name)
    spec = spec_for name

    return false unless spec

    if spec.default_gem?
      say "'#{name}' is a default gem and can't be opened."
      return false
    end

    open_editor(spec.full_gem_path)
  end

  def open_editor(path)
    Dir.chdir(path) do
      system(*@editor.split(/\s+/) + [path])
    end
  end

  def spec_for(name)
    spec = Gem::Specification.find_all_by_name(name, @version).first

    return spec if spec

    say "Unable to find gem '#{name}'"
  end
end
