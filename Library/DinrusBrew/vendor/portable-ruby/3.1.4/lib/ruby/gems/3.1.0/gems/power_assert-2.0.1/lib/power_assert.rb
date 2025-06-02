# power_assert.rb
#
# Copyright (C) 2014 Kazuki Tsujimoto

begin
  unless defined?(Byebug)
    captured = false
    TracePoint.new(:return, :c_return) do |tp|
      captured = true
      unless tp.binding and tp.return_value and tp.callee_id
        raise ''
      end
    end.enable { __id__ }
    raise '' unless captured
  end
rescue
  raise LoadError, 'Fully compatible TracePoint API required'
end

require 'power_assert/context'
require 'power_assert/configuration'
require 'power_assert/version'

module PowerAssert
  POWER_ASSERT_LIB_DIR = File.dirname(caller_locations(1, 1).first.path)
  INTERNAL_LIB_DIRS = {PowerAssert => POWER_ASSERT_LIB_DIR}
  private_constant :POWER_ASSERT_LIB_DIR, :INTERNAL_LIB_DIRS

  class << self
    def start(assertion_proc_or_source, assertion_method: nil, source_binding: TOPLEVEL_BINDING)
      if respond_to?(:clear_global_method_cache, true)
        clear_global_method_cache
      end
      yield BlockContext.new(assertion_proc_or_source, assertion_method, source_binding)
    end

    def trace(frame)
      begin
        raise 'Byebug is not started yet' unless Byebug.started?
      rescue NameError
        raise "PowerAssert.#{__method__} requires Byebug"
      end
      ctx = TraceContext.new(frame._binding)
      ctx.enable
      ctx
    end

    def app_caller_locations
      caller_locations.drop_while {|i| internal_file?(i.path) }.take_while {|i| ! internal_file?(i.path) }
    end

    def app_context?
      top_frame = caller_locations.drop_while {|i| i.path.start_with?(POWER_ASSERT_LIB_DIR) }.first
      top_frame and ! internal_file?(top_frame.path)
    end

    private

    def internal_file?(file)
      setup_internal_lib_dir(Byebug, :attach, 2) if defined?(Byebug)
      setup_internal_lib_dir(PryByebug, :start_with_pry_byebug, 2, Pry) if defined?(PryByebug)
      INTERNAL_LIB_DIRS.find do |_, dir|
        file.start_with?(dir)
      end
    end

    def setup_internal_lib_dir(lib, mid, depth, lib_obj = lib)
      unless INTERNAL_LIB_DIRS.key?(lib)
        INTERNAL_LIB_DIRS[lib] = lib_dir(lib_obj, mid, depth)
      end
    rescue NameError
    end

    def lib_dir(obj, mid, depth)
      File.expand_path('../' * depth, obj.method(mid).source_location[0])
    end

    if defined?(RubyVM)
      CLEAR_CACHE_ISEQ = RubyVM::InstructionSequence.compile('using PowerAssert.const_get(:Empty)')
      private_constant :CLEAR_CACHE_ISEQ

      def clear_global_method_cache
        CLEAR_CACHE_ISEQ.eval
      end
    end
  end

  module Empty
  end
  private_constant :Empty
end
