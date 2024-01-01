# typed: strict
# frozen_string_literal: true

require "formula"
require "cli/parser"

module Homebrew
  module_function

  sig { returns(CLI::Parser) }
  def edit_args
    Homebrew::CLI::Parser.new do
      description <<~EOS
        Open a <formula>, <cask> or <tap> in the editor set by `EDITOR` or `HOMEBREW_EDITOR`,
        or open the Homebrew repository for editing if no argument is provided.
      EOS

      switch "--formula", "--formulae",
             description: "Treat all named arguments as formulae."
      switch "--cask", "--casks",
             description: "Treat all named arguments as casks."
      switch "--print-path",
             description: "Print the file path to be edited, without opening an editor."

      conflicts "--formula", "--cask"

      named_args [:formula, :cask, :tap], without_api: true
    end
  end

  sig { params(path: Pathname).returns(T::Boolean) }
  def core_formula_path?(path)
    path.fnmatch?("**/homebrew-core/Formula/**.rb", File::FNM_DOTMATCH)
  end

  sig { params(path: Pathname).returns(T::Boolean) }
  def core_cask_path?(path)
    path.fnmatch?("**/homebrew-cask/Casks/**.rb", File::FNM_DOTMATCH)
  end

  sig { params(path: Pathname).returns(T::Boolean) }
  def core_formula_tap?(path)
    path == CoreTap.instance.path
  end

  sig { params(path: Pathname).returns(T::Boolean) }
  def core_cask_tap?(path)
    path == CoreCaskTap.instance.path
  end

  sig { params(path: Pathname, cask: T::Boolean).returns(T.noreturn) }
  def raise_with_message!(path, cask)
    name = path.basename(".rb").to_s

    if (tap_match = Regexp.new("#{HOMEBREW_TAP_DIR_REGEX.source}$").match(path.to_s))
      raise TapUnavailableError, CoreTap.instance.name if core_formula_tap?(path)
      raise TapUnavailableError, CoreCaskTap.instance.name if core_cask_tap?(path)

      raise TapUnavailableError, "#{tap_match[:user]}/#{tap_match[:repo]}"
    elsif cask || core_cask_path?(path)
      if !CoreCaskTap.instance.installed? && Homebrew::API::Cask.all_casks.key?(name)
        command = "brew tap --force #{CoreCaskTap.instance.name}"
        action = "tap #{CoreCaskTap.instance.name}"
      else
        command = "brew create --cask --set-name #{name} $URL"
        action = "create a new cask"
      end
    elsif core_formula_path?(path) &&
          !CoreTap.instance.installed? &&
          Homebrew::API::Formula.all_formulae.key?(name)
      command = "brew tap --force #{CoreTap.instance.name}"
      action = "tap #{CoreTap.instance.name}"
    else
      command = "brew create --set-name #{name} $URL"
      action = "create a new formula"
    end

    raise UsageError, <<~EOS
      #{name} doesn't exist on disk.
      Run #{Formatter.identifier(command)} to #{action}!
    EOS
  end

  sig { void }
  def edit
    args = edit_args.parse

    ENV["COLORTERM"] = ENV.fetch("HOMEBREW_COLORTERM", nil)

    unless (HOMEBREW_REPOSITORY/".git").directory?
      odie <<~EOS
        Changes will be lost!
        The first time you `brew update`, all local changes will be lost; you should
        thus `brew update` before you `brew edit`!
      EOS
    end

    paths = if args.named.empty?
      # Sublime requires opting into the project editing path,
      # as opposed to VS Code which will infer from the .vscode path
      if which_editor(silent: true) == "subl"
        ["--project", "#{HOMEBREW_REPOSITORY}/.sublime/homebrew.sublime-project"]
      else
        # If no formulae are listed, open the project root in an editor.
        [HOMEBREW_REPOSITORY]
      end
    else
      expanded_paths = args.named.to_paths
      expanded_paths.each do |path|
        raise_with_message!(path, args.cask?) unless path.exist?
      end

      if expanded_paths.any? do |path|
           (core_formula_path?(path) || core_cask_path?(path) || core_formula_tap?(path) || core_cask_tap?(path)) &&
           !Homebrew::EnvConfig.no_install_from_api? &&
           !Homebrew::EnvConfig.no_env_hints?
         end
        opoo <<~EOS
          `brew install` ignores locally edited casks and formulae if
          HOMEBREW_NO_INSTALL_FROM_API is not set.
        EOS
      end
      expanded_paths
    end

    if args.print_path?
      paths.each(&method(:puts))
      return
    end

    exec_editor(*paths)
  end
end
