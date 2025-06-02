require 'power_assert/configuration'
require 'power_assert/enable_tracepoint_events'
require 'power_assert/inspector'
require 'power_assert/parser'

module PowerAssert
  class Context
    Value = Struct.new(:name, :value, :lineno, :column, :display_offset)

    def initialize(base_caller_length)
      @fired = false
      @target_thread = Thread.current
      method_id_set = nil
      @return_values = []
      @trace_return = TracePoint.new(:return, :c_return) do |tp|
        unless method_id_set
          next unless Thread.current == @target_thread
          method_id_set = @parser.method_id_set
        end
        method_id = tp.callee_id
        next if ! method_id_set[method_id]
        next if tp.event == :c_return and
                not (@parser.lineno == tp.lineno and @parser.path == tp.path)
        locs = PowerAssert.app_caller_locations
        diff = locs.length - base_caller_length
        if (tp.event == :c_return && diff == 1 || tp.event == :return && diff <= 2) and Thread.current == @target_thread
          idx = -(base_caller_length + 1)
          if @parser.path == locs[idx].path and @parser.lineno == locs[idx].lineno
            val = PowerAssert.configuration.lazy_inspection ?
              tp.return_value :
              InspectedValue.new(SafeInspectable.new(tp.return_value).inspect)
            @return_values << Value[method_id.to_s, val, locs[idx].lineno, nil]
          end
        end
      rescue Exception => e
        warn "power_assert: [BUG] Failed to trace: #{e.class}: #{e.message}"
        if e.respond_to?(:full_message)
          warn e.full_message.gsub(/^/, 'power_assert:     ')
        end
      end
    end

    def message
      raise 'call #yield or #enable at first' unless fired?
      @message ||= build_assertion_message(@parser, @return_values).freeze
    end

    def message_proc
      -> { message }
    end

    private

    def fired?
      @fired
    end

    def build_assertion_message(parser, return_values)
      if PowerAssert.configuration.colorize_message
        line = IRB::Color.colorize_code(parser.line, ignore_error: true)
      else
        line = parser.line
      end

      path = detect_path(parser, return_values)
      return line unless path

      c2d = column2display_offset(parser.line)
      return_values, methods_in_path = find_all_identified_calls(return_values, path)
      return_values.zip(methods_in_path) do |i, j|
        unless i.name == j.name
          warn "power_assert: [BUG] Failed to get column: #{i.name}"
          return line
        end
        i.display_offset = c2d[j.column]
      end
      refs_in_path = path.find_all {|i| i.type == :ref }
      ref_values = refs_in_path.map {|i| Value[i.name, parser.binding.eval(i.name), parser.lineno, i.column, c2d[i.column]] }
      vals = (return_values + ref_values).find_all(&:display_offset).sort_by(&:display_offset).reverse
      return line if vals.empty?

      fmt = (0..vals[0].display_offset).map do |i|
        if vals.find {|v| v.display_offset == i }
          "%<#{i}>s"
        else
          line[i] == "\t" ? "\t" : ' '
        end
      end.join
      lines = []
      lines << line.chomp
      lines << sprintf(fmt, vals.each_with_object({}) {|v, h| h[:"#{v.display_offset}"] = '|' }).chomp
      vals.each do |i|
        inspected_val = SafeInspectable.new(Inspector.new(i.value, i.display_offset)).inspect
        inspected_val.each_line do |l|
          map_to = vals.each_with_object({}) do |j, h|
            h[:"#{j.display_offset}"] = [l, '|', ' '][i.display_offset <=> j.display_offset]
          end
          lines << encoding_safe_rstrip(sprintf(fmt, map_to))
        end
      end
      lines.join("\n")
    end

    def detect_path(parser, return_values)
      return parser.call_paths.flatten.uniq if parser.method_id_set.empty?
      all_paths = parser.call_paths
      return_value_names = return_values.map(&:name)
      uniq_calls = uniq_calls(all_paths)
      uniq_call = return_value_names.find {|i| uniq_calls.include?(i) }
      detected_paths = all_paths.find_all do |path|
        method_names = path.find_all {|ident| ident.type == :method }.map(&:name)
        break [path] if uniq_call and method_names.include?(uniq_call)
        return_value_names == method_names
      end
      return nil unless detected_paths.length == 1
      detected_paths[0]
    end

    def uniq_calls(paths)
      all_calls = enum_count_by(paths.map {|path| path.find_all {|ident| ident.type == :method }.map(&:name).uniq }.flatten) {|i| i }
      all_calls.find_all {|_, call_count| call_count == 1 }.map {|name, _| name }
    end

    def find_all_identified_calls(return_values, path)
      return_value_num_of_calls = enum_count_by(return_values, &:name)
      path_num_of_calls = enum_count_by(path.find_all {|ident| ident.type == :method }, &:name)
      identified_calls = return_value_num_of_calls.find_all {|name, num| path_num_of_calls[name] == num }.map(&:first)
      [
        return_values.find_all {|val| identified_calls.include?(val.name) },
        path.find_all {|ident| ident.type == :method and identified_calls.include?(ident.name)  }
      ]
    end

    def enum_count_by(enum, &blk)
      Hash[enum.group_by(&blk).map{|k, v| [k, v.length] }]
    end

    def encoding_safe_rstrip(str)
      str.rstrip
    rescue ArgumentError, Encoding::CompatibilityError
      enc = str.encoding
      if enc.ascii_compatible?
        str.b.rstrip.force_encoding(enc)
      else
        str
      end
    end

    def column2display_offset(str)
      display_offset = 0
      str.each_char.with_object([]) do |c, r|
        c.bytesize.times do
          r << display_offset
        end
        display_offset += c.ascii_only? ? 1 : 2 # FIXME
      end
    end
  end
  private_constant :Context

  class BlockContext < Context
    def initialize(assertion_proc_or_source, assertion_method, source_binding)
      super(0)
      if assertion_proc_or_source.respond_to?(:to_proc)
        @assertion_proc = assertion_proc_or_source.to_proc
        line = nil
      else
        @assertion_proc = source_binding.eval "Proc.new {#{assertion_proc_or_source}}"
        line = assertion_proc_or_source
      end
      @parser = Parser::DUMMY
      @trace_call = TracePoint.new(:call, :c_call) do
        if PowerAssert.app_context? and Thread.current == @target_thread
          @trace_call.disable
          locs = PowerAssert.app_caller_locations
          path = locs.last.path
          lineno = locs.last.lineno
          if File.exist?(path)
            line ||= File.open(path) {|fp| fp.each_line.drop(lineno - 1).first }
          end
          if line
            @parser = Parser.new(line, path, lineno, @assertion_proc.binding, assertion_method.to_s, @assertion_proc)
          end
        end
      end
    end

    def yield
      @fired = true
      invoke_yield(&@assertion_proc)
    end

    private

    def invoke_yield
      @trace_return.enable do
        @trace_call.enable do
          yield
        end
      end
    end
  end
  private_constant :BlockContext

  class TraceContext < Context
    def initialize(binding)
      target_frame, *base = PowerAssert.app_caller_locations
      super(base.length)
      path = target_frame.path
      lineno = target_frame.lineno
      if File.exist?(path)
        line = File.open(path) {|fp| fp.each_line.drop(lineno - 1).first }
        @parser = Parser.new(line, path, lineno, binding)
      else
        @parser = Parser::DUMMY
      end
    end

    def enable
      @fired = true
      @trace_return.enable
    end

    def disable
      @trace_return.disable
    end

    def enabled?
      @trace_return.enabled?
    end
  end
  private_constant :TraceContext
end
