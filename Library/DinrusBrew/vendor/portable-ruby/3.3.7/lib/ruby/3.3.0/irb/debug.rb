# frozen_string_literal: true

module IRB
  module Debug
    IRB_DIR = File.expand_path('..', __dir__)

    class << self
      def insert_debug_break(pre_cmds: nil, do_cmds: nil)
        options = { oneshot: true, hook_call: false }

        if pre_cmds || do_cmds
          options[:command] = ['irb', pre_cmds, do_cmds]
        end
        if DEBUGGER__::LineBreakpoint.instance_method(:initialize).parameters.include?([:key, :skip_src])
          options[:skip_src] = true
        end

        # To make debugger commands like `next` or `continue` work without asking
        # the user to quit IRB after that, we need to exit IRB first and then hit
        # a TracePoint on #debug_break.
        file, lineno = IRB::Irb.instance_method(:debug_break).source_location
        DEBUGGER__::SESSION.add_line_breakpoint(file, lineno + 1, **options)
      end

      def setup(irb)
        # When debug session is not started at all
        unless defined?(DEBUGGER__::SESSION)
          begin
            require "debug/session"
          rescue LoadError # debug.gem is not written in Gemfile
            return false unless load_bundled_debug_gem
          end
          DEBUGGER__::CONFIG.set_config
          configure_irb_for_debugger(irb)

          DEBUGGER__.initialize_session{ IRB::Debug::UI.new(irb) }
        end

        # When debug session was previously started but not by IRB
        if defined?(DEBUGGER__::SESSION) && !irb.context.with_debugger
          configure_irb_for_debugger(irb)
          DEBUGGER__::SESSION.reset_ui(IRB::Debug::UI.new(irb))
        end

        # Apply patches to debug gem so it skips IRB frames
        unless DEBUGGER__.respond_to?(:capture_frames_without_irb)
          DEBUGGER__.singleton_class.send(:alias_method, :capture_frames_without_irb, :capture_frames)

          def DEBUGGER__.capture_frames(*args)
            frames = capture_frames_without_irb(*args)
            frames.reject! do |frame|
              frame.realpath&.start_with?(IRB_DIR) || frame.path == "<internal:prelude>"
            end
            frames
          end

          DEBUGGER__::ThreadClient.prepend(SkipPathHelperForIRB)
        end

        if !@output_modifier_defined && !DEBUGGER__::CONFIG[:no_hint]
          irb_output_modifier_proc = Reline.output_modifier_proc

          Reline.output_modifier_proc = proc do |output, complete:|
            unless output.strip.empty?
              cmd = output.split(/\s/, 2).first

              if !complete && DEBUGGER__.commands.key?(cmd)
                output = output.sub(/\n$/, " # debug command\n")
              end
            end

            irb_output_modifier_proc.call(output, complete: complete)
          end

          @output_modifier_defined = true
        end

        true
      end

      private

      def configure_irb_for_debugger(irb)
        require 'irb/debug/ui'
        IRB.instance_variable_set(:@debugger_irb, irb)
        irb.context.with_debugger = true
        irb.context.irb_name += ":rdbg"
      end

      module SkipPathHelperForIRB
        def skip_internal_path?(path)
          # The latter can be removed once https://github.com/ruby/debug/issues/866 is resolved
          super || path.match?(IRB_DIR) || path.match?('<internal:prelude>')
        end
      end

      # This is used when debug.gem is not written in Gemfile. Even if it's not
      # installed by `bundle install`, debug.gem is installed by default because
      # it's a bundled gem. This method tries to activate and load that.
      def load_bundled_debug_gem
        # Discover latest debug.gem under GEM_PATH
        debug_gem = Gem.paths.path.flat_map { |path| Dir.glob("#{path}/gems/debug-*") }.select do |path|
          File.basename(path).match?(/\Adebug-\d+\.\d+\.\d+(\w+)?\z/)
        end.sort_by do |path|
          Gem::Version.new(File.basename(path).delete_prefix('debug-'))
        end.last
        return false unless debug_gem

        # Discover debug/debug.so under extensions for Ruby 3.2+
        ext_name = "/debug/debug.#{RbConfig::CONFIG['DLEXT']}"
        ext_path = Gem.paths.path.flat_map do |path|
          Dir.glob("#{path}/extensions/**/#{File.basename(debug_gem)}#{ext_name}")
        end.first

        # Attempt to forcibly load the bundled gem
        if ext_path
          $LOAD_PATH << ext_path.delete_suffix(ext_name)
        end
        $LOAD_PATH << "#{debug_gem}/lib"
        begin
          require "debug/session"
          puts "Loaded #{File.basename(debug_gem)}"
          true
        rescue LoadError
          false
        end
      end
    end
  end
end
