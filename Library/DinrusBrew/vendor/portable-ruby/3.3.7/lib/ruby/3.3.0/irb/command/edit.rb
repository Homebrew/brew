require 'shellwords'

require_relative "../color"
require_relative "../source_finder"

module IRB
  # :stopdoc:

  module Command
    class Edit < Base
      include RubyArgsExtractor

      category "Misc"
      description 'Open a file or source location.'
      help_message <<~HELP_MESSAGE
        Usage: edit [FILE or constant or method signature]

        Open a file in the editor specified in #{highlight('ENV["VISUAL"]')} or #{highlight('ENV["EDITOR"]')}

        - If no arguments are provided, IRB will attempt to open the file the current context was defined in.
        - If FILE is provided, IRB will open the file.
        - If a constant or method signature is provided, IRB will attempt to locate the source file and open it.

        Examples:

          edit
          edit foo.rb
          edit Foo
          edit Foo#bar
      HELP_MESSAGE

      def execute(arg)
        # Accept string literal for backward compatibility
        path = unwrap_string_literal(arg)

        if path.nil?
          path = @irb_context.irb_path
        elsif !File.exist?(path)
          source = SourceFinder.new(@irb_context).find_source(path)

          if source&.file_exist? && !source.binary_file?
            path = source.file
          end
        end

        unless File.exist?(path)
          puts "Can not find file: #{path}"
          return
        end

        if editor = (ENV['VISUAL'] || ENV['EDITOR'])
          puts "command: '#{editor}'"
          puts "   path: #{path}"
          system(*Shellwords.split(editor), path)
        else
          puts "Can not find editor setting: ENV['VISUAL'] or ENV['EDITOR']"
        end
      end
    end
  end

  # :startdoc:
end
