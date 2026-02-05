# typed: strict
# frozen_string_literal: true

require "fileutils"
require "utils/output"

module Homebrew
  module Aliases
    class Alias
      include ::Utils::Output::Mixin

      sig { returns(String) }
      attr_accessor :name

      sig { returns(T.nilable(String)) }
      attr_accessor :command

      sig { params(name: String, command: T.nilable(String)).void }
      def initialize(name, command = nil)
        @name = T.let(name.strip, String)
        @command = T.let(nil, T.nilable(String))
        @script = T.let(nil, T.nilable(Pathname))
        @symlink = T.let(nil, T.nilable(Pathname))

        @command = if command&.start_with?("!", "%")
          command[1..]
        elsif command
          "brew #{command}"
        end
      end

      sig { returns(T::Boolean) }
      def reserved?
        RESERVED.include? name
      end

      sig { returns(T::Boolean) }
      def cmd_exists?
        path = which("brew-#{name}.rb") || which("brew-#{name}")
        !path.nil? && path.realpath.parent != HOMEBREW_ALIASES
      end

      sig { returns(Pathname) }
      def script
        @script ||= Pathname.new("#{HOMEBREW_ALIASES}/#{name.gsub(/\W/, "_")}")
      end

      sig { returns(Pathname) }
      def symlink
        @symlink ||= Pathname.new("#{HOMEBREW_PREFIX}/bin/brew-#{name}")
      end

      sig { returns(T::Boolean) }
      def valid_symlink?
        symlink.realpath.parent == HOMEBREW_ALIASES.realpath
      rescue NameError
        false
      end

      sig { void }
      def link
        FileUtils.rm symlink if File.symlink? symlink
        FileUtils.ln_s script, symlink
      end

      sig { params(opts: T::Hash[Symbol, T::Boolean]).void }
      def write(opts = {})
        odie "'#{name}' is a reserved command. Sorry." if reserved?
        odie "'brew #{name}' already exists. Sorry." if cmd_exists?

        return if !opts[:override] && script.exist?

        content = if command
          <<~EOS
            #:  * `#{name}` [args...]
            #:    `brew #{name}` is an alias for `#{command}`
            #{command} $*
          EOS
        else
          <<~EOS
            #:  * `#{name}` [args...]
            #:    `brew #{name}` is an alias for *command*

            # This is a Homebrew alias script. It'll be called when the user
            # types `brew #{name}`. Any remaining arguments are passed to
            # this script. You can retrieve those with $*, or only the first
            # one with $1. Please keep your script on one line.

            # TODO: Replace the line below with your script
            echo "Hello I'm 'brew "#{name}"' and my args are:" $*
          EOS
        end

        script.open("w") do |f|
          f.write <<~EOS
            #! #{`which bash`.chomp}
            # alias: brew #{name}
            #{content}
          EOS
        end
        script.chmod 0744
        link
      end

      sig { void }
      def remove
        odie "'brew #{name}' is not aliased to anything." if !symlink.exist? || !valid_symlink?

        script.unlink
        symlink.unlink
      end

      sig { void }
      def edit
        write(override: false)
        exec_editor script.to_s
      end
    end
  end
end
