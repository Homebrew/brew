# typed: strict
# frozen_string_literal: true

require "aliases/alias"

module Homebrew
  module Aliases
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

    sig { params(only: T::Array[String], block: T.proc.params(target: String, cmd: String).void).void }
    def self.each(only, &block)
      Dir["#{HOMEBREW_ALIASES}/*"].each do |path|
        next if path.end_with? "~" # skip Emacs-like backup files
        next if File.directory?(path)

        _shebang, _meta, *lines = File.readlines(path)
        target = File.basename(path)
        next if !only.empty? && only.exclude?(target)

        lines.reject! { |line| line.start_with?("#") || line =~ /^\s*$/ }
        first_line = T.must(lines.first)
        cmd = first_line.chomp
        cmd.sub!(/ \$\*$/, "")

        if cmd.start_with? "brew "
          cmd.sub!(/^brew /, "")
        else
          cmd = "!#{cmd}"
        end

        yield target, cmd if block.present?
      end
    end

    sig { params(aliases: String).void }
    def self.show(*aliases)
      each([*aliases]) do |target, cmd|
        puts "brew alias #{target}='#{cmd}'"
        existing_alias = Alias.new(target, cmd)
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
