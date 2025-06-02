# frozen_string_literal: true
module DEBUGGER__
  class Console
    begin
      raise LoadError if CONFIG[:no_reline]
      require 'reline'

      require_relative 'color'

      include Color

      def parse_input buff, commands
        c, rest = get_command buff
        case
        when commands.keys.include?(c)
          :command
        when !rest && /\A\s*[a-z]*\z/ =~ c
          nil
        else
          :ruby
        end
      end

      def readline_setup prompt
        load_history_if_not_loaded
        commands = DEBUGGER__.commands

        prev_completion_proc = Reline.completion_proc
        prev_output_modifier_proc = Reline.output_modifier_proc
        prev_prompt_proc = Reline.prompt_proc

        # prompt state
        state = nil # :command, :ruby, nil (unknown)

        Reline.prompt_proc = -> args, *kw do
          case state = parse_input(args.first, commands)
          when nil, :command
            [prompt]
          when :ruby
            [prompt.sub('rdbg'){colorize('ruby', [:RED])}]
          end * args.size
        end

        Reline.completion_proc = -> given do
          buff = Reline.line_buffer
          Reline.completion_append_character= ' '

          if /\s/ =~ buff # second parameters
            given = File.expand_path(given + 'a').sub(/a\z/, '')
            files = Dir.glob(given + '*')
            if files.size == 1 && File.directory?(files.first)
              Reline.completion_append_character= '/'
            end
            files
          else
            commands.keys.grep(/\A#{Regexp.escape(given)}/)
          end
        end

        Reline.output_modifier_proc = -> buff, **kw do
          c, rest = get_command buff

          case state
          when :command
            cmd = colorize(c, [:CYAN, :UNDERLINE])

            if commands[c] == c
              rprompt = colorize("    # command", [:DIM])
            else
              rprompt = colorize("    # #{commands[c]} command", [:DIM])
            end

            rest = rest ? colorize_code(rest) : ''
            cmd + rest + rprompt
          when nil
            buff
          when :ruby
            colorize_code(buff)
          end
        end unless CONFIG[:no_hint]

        yield

      ensure
        Reline.completion_proc = prev_completion_proc
        Reline.output_modifier_proc = prev_output_modifier_proc
        Reline.prompt_proc = prev_prompt_proc
      end

      private def get_command line
        case line.chomp
        when /\A(\s*[a-z]+)(\s.*)?\z$/
          return $1.strip, $2
        else
          line.strip
        end
      end

      def readline prompt
        readline_setup prompt do
          Reline.readmultiline(prompt, true){ true }
        end
      end

      def history
        Reline::HISTORY
      end

    rescue LoadError
      begin
        require 'readline.so'

        def readline_setup
          load_history_if_not_loaded
          commands = DEBUGGER__.commands

          Readline.completion_proc = proc{|given|
            buff = Readline.line_buffer
            Readline.completion_append_character= ' '

            if /\s/ =~ buff # second parameters
              given = File.expand_path(given + 'a').sub(/a\z/, '')
              files = Dir.glob(given + '*')
              if files.size == 1 && File.directory?(files.first)
                Readline.completion_append_character= '/'
              end
              files
            else
              commands.keys.grep(/\A#{given}/)
            end
          }
        end

        def readline prompt
          readline_setup
          Readline.readline(prompt, true)
        end

        def history
          Readline::HISTORY
        end

      rescue LoadError
        def readline prompt
          print prompt
          $stdin.gets
        end

        def history
          nil
        end
      end
    end

    def history_file
      history_file = CONFIG[:history_file]

      if !history_file.empty?
        File.expand_path(history_file)
      else
        history_file
      end
    end

    FH = "# Today's OMIKUJI: "

    def read_history_file
      if history && File.exist?(path = history_file)
        f = (['', 'DAI-', 'CHU-', 'SHO-'].map{|e| e+'KICHI'}+['KYO']).sample
        ["#{FH}#{f}".dup] + File.readlines(path)
      else
        []
      end
    end

    def initialize
      @init_history_lines = nil
    end

    def load_history_if_not_loaded
      return if @init_history_lines

      @init_history_lines = load_history
    end

    def deactivate
      if history && @init_history_lines
        added_records = history.to_a[@init_history_lines .. -1]
        path = history_file
        max = CONFIG[:save_history]

        if !added_records.empty? && !path.empty?
          orig_records = read_history_file
          open(history_file, 'w'){|f|
            (orig_records + added_records).last(max).each{|line|
              if !line.start_with?(FH) && !line.strip.empty?
                f.puts line.strip
              end
            }
          }
        end
      end
    end

    def load_history
      read_history_file.each{|line|
        line.strip!
        history << line unless line.empty?
      } if history.empty?
      history.count
    end
  end # class Console
end
