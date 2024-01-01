# frozen_string_literal: true

require "delegate"

module Test
  module Helper
    module OutputAsTTY
      # This is a custom wrapper for the `output` matcher,
      # used for testing output to a TTY:
      #
      #   expect {
      #     print "test" if $stdout.tty?
      #   }.to output("test").to_stdout.as_tty
      #
      #   expect {
      #     # command
      #   }.to output(...).to_stderr.as_tty.with_color
      #
      class Output < SimpleDelegator
        def matches?(block)
          return super(block) unless @tty

          colored_tty_block = lambda do
            instance_eval("$#{@output}  # $stdout", __FILE__, __LINE__).extend(Module.new do
              def tty?
                true
              end

              alias_method :isatty, :tty?
            end)
            block.call
          end

          return super(colored_tty_block) if @colors

          uncolored_tty_block = lambda do
            instance_eval <<-EOS, __FILE__, __LINE__ + 1
              begin                                                       # begin
                captured_stream = StringIO.new                            #   captured_stream = StringIO.new

                original_stream = $#{@output}                             #   original_stream = $stdout
                $#{@output} = captured_stream                             #   $stdout = captured_stream

                colored_tty_block.call                                    #   colored_tty_block.call
              ensure                                                      # ensure
                $#{@output} = original_stream                             #   $stdout = original_stream
                $#{@output}.print Tty.strip_ansi(captured_stream.string)  #   $stdout.print Tty.strip_ansi(captured_stream.string)
              end                                                         # end
            EOS
          end

          super(uncolored_tty_block)
        end

        def to_stdout
          @output = :stdout
          super
          self
        end

        def to_stderr
          @output = :stderr
          super
          self
        end

        def as_tty
          @tty = true
          return self if [:stdout, :stderr].include?(@output)

          raise "`as_tty` can only be chained to `stdout` or `stderr`."
        end

        def with_color
          @colors = true
          return self if @tty

          raise "`with_color` can only be chained to `as_tty`."
        end
      end

      def output(*args)
        core_matcher = super(*args)
        Output.new(core_matcher)
      end
    end
  end
end
