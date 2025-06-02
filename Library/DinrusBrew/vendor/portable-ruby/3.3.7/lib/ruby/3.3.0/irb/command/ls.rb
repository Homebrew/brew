# frozen_string_literal: true

require "reline"
require "stringio"

require_relative "../pager"
require_relative "../color"

module IRB
  # :stopdoc:

  module Command
    class Ls < Base
      include RubyArgsExtractor

      category "Context"
      description "Show methods, constants, and variables."

      help_message <<~HELP_MESSAGE
        Usage: ls [obj] [-g [query]]

          -g [query]  Filter the output with a query.
      HELP_MESSAGE

      def execute(arg)
        if match = arg.match(/\A(?<target>.+\s|)(-g|-G)\s+(?<grep>.+)$/)
          if match[:target].empty?
            use_main = true
          else
            obj = @irb_context.workspace.binding.eval(match[:target])
          end
          grep = Regexp.new(match[:grep])
        else
          args, kwargs = ruby_args(arg)
          use_main = args.empty?
          obj = args.first
          grep = kwargs[:grep]
        end

        if use_main
          obj = irb_context.workspace.main
          locals = irb_context.workspace.binding.local_variables
        end

        o = Output.new(grep: grep)

        klass  = (obj.class == Class || obj.class == Module ? obj : obj.class)

        o.dump("constants", obj.constants) if obj.respond_to?(:constants)
        dump_methods(o, klass, obj)
        o.dump("instance variables", obj.instance_variables)
        o.dump("class variables", klass.class_variables)
        o.dump("locals", locals) if locals
        o.print_result
      end

      def dump_methods(o, klass, obj)
        singleton_class = begin obj.singleton_class; rescue TypeError; nil end
        dumped_mods = Array.new
        ancestors = klass.ancestors
        ancestors = ancestors.reject { |c| c >= Object } if klass < Object
        singleton_ancestors = (singleton_class&.ancestors || []).reject { |c| c >= Class }

        # singleton_class' ancestors should be at the front
        maps = class_method_map(singleton_ancestors, dumped_mods) + class_method_map(ancestors, dumped_mods)
        maps.each do |mod, methods|
          name = mod == singleton_class ? "#{klass}.methods" : "#{mod}#methods"
          o.dump(name, methods)
        end
      end

      def class_method_map(classes, dumped_mods)
        dumped_methods = Array.new
        classes.map do |mod|
          next if dumped_mods.include? mod

          dumped_mods << mod

          methods = mod.public_instance_methods(false).select do |method|
            if dumped_methods.include? method
              false
            else
              dumped_methods << method
              true
            end
          end

          [mod, methods]
        end.compact
      end

      class Output
        MARGIN = "  "

        def initialize(grep: nil)
          @grep = grep
          @line_width = screen_width - MARGIN.length # right padding
          @io = StringIO.new
        end

        def print_result
          Pager.page_content(@io.string)
        end

        def dump(name, strs)
          strs = strs.grep(@grep) if @grep
          strs = strs.sort
          return if strs.empty?

          # Attempt a single line
          @io.print "#{Color.colorize(name, [:BOLD, :BLUE])}: "
          if fits_on_line?(strs, cols: strs.size, offset: "#{name}: ".length)
            @io.puts strs.join(MARGIN)
            return
          end
          @io.puts

          # Dump with the largest # of columns that fits on a line
          cols = strs.size
          until fits_on_line?(strs, cols: cols, offset: MARGIN.length) || cols == 1
            cols -= 1
          end
          widths = col_widths(strs, cols: cols)
          strs.each_slice(cols) do |ss|
            @io.puts ss.map.with_index { |s, i| "#{MARGIN}%-#{widths[i]}s" % s }.join
          end
        end

        private

        def fits_on_line?(strs, cols:, offset: 0)
          width = col_widths(strs, cols: cols).sum + MARGIN.length * (cols - 1)
          width <= @line_width - offset
        end

        def col_widths(strs, cols:)
          cols.times.map do |col|
            (col...strs.size).step(cols).map do |i|
              strs[i].length
            end.max
          end
        end

        def screen_width
          Reline.get_screen_size.last
        rescue Errno::EINVAL # in `winsize': Invalid argument - <STDIN>
          80
        end
      end
      private_constant :Output
    end
  end

  # :startdoc:
end
