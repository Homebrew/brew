# frozen_string_literal: true

require_relative 'color'

module DEBUGGER__
  class SourceRepository
    include Color

    def file_src iseq
      if (path = (iseq.absolute_path || iseq.path)) && File.exist?(path)
        File.readlines(path, chomp: true)
      end
    end

    def get iseq
      return unless iseq

      if CONFIG[:show_evaledsrc]
        orig_src(iseq) || file_src(iseq)
      else
        file_src(iseq) || orig_src(iseq)
      end
    end

    if defined?(RubyVM.keep_script_lines)
      # Ruby 3.1 and later
      RubyVM.keep_script_lines = true
      require 'objspace'

      def initialize
        # cache
        @cmap = ObjectSpace::WeakMap.new
        @loaded_file_map = {} # path => nil
      end

      def add iseq, src
        # only manage loaded file names
        if (path = (iseq.absolute_path || iseq.path)) && File.exist?(path)
          if @loaded_file_map.has_key? path
            return path, true # reloaded
          else
            @loaded_file_map[path] = path
            return path, false
          end
        end
      end

      def orig_src iseq
        lines = iseq.script_lines&.map(&:chomp)
        line = iseq.first_line
        if line > 1
          [*([''] * (line - 1)), *lines]
        else
          lines
        end
      end

      def get_colored iseq
        if lines = @cmap[iseq]
          lines
        else
          if src_lines = get(iseq)
            @cmap[iseq] = colorize_code(src_lines.join("\n")).lines
          else
            nil
          end
        end
      end
    else
      # ruby 3.0 or earlier
      SrcInfo = Struct.new(:src, :colored)

      def initialize
        @files = {} # filename => SrcInfo
      end

      def add iseq, src
        path = (iseq.absolute_path || iseq.path)

        if path && File.exist?(path)
          reloaded = @files.has_key? path

          if src
            add_iseq iseq, src
            return path, reloaded
          else
            add_path path
            return path, reloaded
          end
        else
          add_iseq iseq, src
          nil
        end
      end

      private def all_iseq iseq, rs = []
        rs << iseq
        iseq.each_child{|ci|
          all_iseq(ci, rs)
        }
        rs
      end

      private def add_iseq iseq, src
        line = iseq.first_line
        if line > 1
          src = ("\n" * (line - 1)) + src
        end

        si = SrcInfo.new(src.each_line.map{|l| l.chomp})
        all_iseq(iseq).each{|e|
          e.instance_variable_set(:@debugger_si, si)
          e.freeze
        }
      end

      private def add_path path
        src_lines = File.readlines(path, chomp: true)
        @files[path] = SrcInfo.new(src_lines)
      rescue SystemCallError
      end

      private def get_si iseq
        return unless iseq

        if iseq.instance_variable_defined?(:@debugger_si)
          iseq.instance_variable_get(:@debugger_si)
        elsif @files.has_key?(path = (iseq.absolute_path || iseq.path))
          @files[path]
        elsif path
          add_path(path)
        end
      end

      def orig_src iseq
        if si = get_si(iseq)
          si.src
        end
      end

      def get_colored iseq
        if si = get_si(iseq)
          si.colored || begin
            si.colored = colorize_code(si.src.join("\n")).lines
          end
        end
      end
    end
  end
end
