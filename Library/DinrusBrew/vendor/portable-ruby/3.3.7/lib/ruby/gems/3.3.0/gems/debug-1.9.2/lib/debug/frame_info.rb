# frozen_string_literal: true

module DEBUGGER__
  FrameInfo = Struct.new(:location, :self, :binding, :iseq, :class, :frame_depth,
                          :has_return_value,     :return_value,
                          :has_raised_exception, :raised_exception,
                          :show_line,
                          :_local_variables, :_callee, # for recorder
                          :dupped_binding,
                        )

  # extend FrameInfo with debug.so
  begin
    require_relative 'debug.so'
  rescue LoadError
    require 'debug/debug.so'
  end

  class FrameInfo
    HOME = ENV['HOME'] ? (ENV['HOME'] + '/') : nil

    def path
      location.path
    end

    def realpath
      location.absolute_path
    end

    def self.pretty_path path
      return '#<none>' unless path
      use_short_path = CONFIG[:use_short_path]

      case
      when use_short_path && path.start_with?(dir = RbConfig::CONFIG["rubylibdir"] + '/')
        path.sub(dir, '$(rubylibdir)/')
      when use_short_path && Gem.path.any? do |gp|
          path.start_with?(dir = gp + '/gems/')
        end
        path.sub(dir, '$(Gem)/')
      when HOME && path.start_with?(HOME)
        path.sub(HOME, '~/')
      else
        path
      end
    end

    def pretty_path
      FrameInfo.pretty_path path
    end

    def name
      # p frame_type: frame_type, self: self
      case frame_type
      when :block
        level, block_loc = block_identifier
        "block in #{block_loc}#{level}"
      when :method
        method_identifier
      when :c
        c_identifier
      when :other
        other_identifier
      end
    end

    def file_lines
      SESSION.source(self.iseq)
    end

    def frame_type
      if self.local_variables && iseq
        if iseq.type == :block
          :block
        elsif callee
          :method
        else
          :other
        end
      else
        :c
      end
    end

    BLOCK_LABL_REGEXP = /\Ablock( \(\d+ levels\))* in (.+)\z/

    def block_identifier
      return unless frame_type == :block
      _, level, block_loc = location.label.match(BLOCK_LABL_REGEXP).to_a
      [level || "", block_loc]
    end

    def method_identifier
      return unless frame_type == :method
      "#{klass_sig}#{callee}"
    end

    def c_identifier
      return unless frame_type == :c
      "[C] #{klass_sig}#{location.base_label}"
    end

    def other_identifier
      return unless frame_type == :other
      location.label
    end

    def callee
      self._callee ||= begin
                         self.binding&.eval('__callee__')
                       rescue NameError # BasicObject
                         nil
                       end
    end

    def return_str
      if self.binding && iseq && has_return_value
        DEBUGGER__.safe_inspect(return_value, short: true)
      end
    end

    def matchable_location
      # realpath can sometimes be nil so we can't use it here
      "#{path}:#{location.lineno}"
    end

    def location_str
      "#{pretty_path}:#{location.lineno}"
    end

    def eval_binding
      if b = self.dupped_binding
        b
      else
        b = self.binding || TOPLEVEL_BINDING
        self.dupped_binding = b.dup
      end
    end

    def local_variables
      if lvars = self._local_variables
        lvars
      elsif b = self.binding
        b.local_variables.map{|var|
          [var, b.local_variable_get(var)]
        }.to_h
      end
    end

    def iseq_parameters_info
      case frame_type
      when :block, :method
        parameters_info
      else
        nil
      end
    end

    def parameters_info
      vars = iseq.parameters_symbols
      vars.map{|var|
        begin
          { name: var, value: DEBUGGER__.safe_inspect(local_variable_get(var), short: true) }
        rescue NameError, TypeError
          nil
        end
      }.compact
    end

    private def get_singleton_class obj
      obj.singleton_class # TODO: don't use it
    rescue TypeError
      nil
    end

    private def local_variable_get var
      local_variables[var]
    end

    private def klass_sig
      if self.class == get_singleton_class(self.self)
        "#{self.self}."
      else
        "#{self.class}#"
      end
    end
  end
end
