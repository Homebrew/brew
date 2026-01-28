# typed: strict
# frozen_string_literal: true

require "aliases/alias"
require "utils/output"

module Homebrew
  module Aliases
    extend Utils::Output::Mixin

    RESERVED = T.let((
        Commands.internal_commands +
        Commands.internal_developer_commands +
        Commands.internal_commands_aliases +
        %w[alias unalias]
      ).freeze, T::Array[String])

    sig { void }
    def self.init
      FileUtils.mkdir_p HOMEBREW_ALIASES
    end

    sig { params(name: String, command: String).void }
    def self.add(name, command)
      new_alias = Alias.new(name, command)
      odie "alias 'brew #{name}' already exists!" if new_alias.script.exist?
      new_alias.write
    end

    sig { params(name: String).void }
    def self.remove(name)
      Alias.new(name).remove
    end

    sig { params(only: T::Array[String], block: T.proc.params(name: String, command: String).void).void }
    def self.each(only, &block)
      Dir["#{HOMEBREW_ALIASES}/*"].each do |path|
        next if path.end_with? "~" # skip Emacs-like backup files
        next if File.directory?(path)

        _shebang, meta, *lines = File.readlines(path)
        name = T.must(meta)[/alias: brew (\S+)/, 1] || File.basename(path)
        next if !only.empty? && only.exclude?(name)

        lines.reject! { |line| line.start_with?("#") || line =~ /^\s*$/ }
        first_line = lines.fetch(0)
        command = first_line.chomp
        command.sub!(/ \$\*$/, "")

        if command.start_with? "brew "
          command.sub!(/^brew /, "")
        else
          command = "!#{command}"
        end

        yield name, command if block.present?
      end
    end

    sig { params(aliases: String).void }
    def self.show(*aliases)
      each([*aliases]) do |name, command|
        puts "brew alias #{name}='#{command}'"
        existing_alias = Alias.new(name, command)
        existing_alias.link unless existing_alias.symlink.exist?
      end
    end

    sig { params(name: String, command: T.nilable(String)).void }
    def self.edit(name, command = nil)
      Alias.new(name, command).write unless command.nil?
      Alias.new(name, command).edit
    end

    sig { void }
    def self.edit_all
      exec_editor(*Dir[HOMEBREW_ALIASES])
    end
  end
end
