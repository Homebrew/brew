# frozen_string_literal: true
#
#   loader.rb -
#   	by Keiju ISHITSUKA(keiju@ruby-lang.org)
#

module IRB # :nodoc:
  # Raised in the event of an exception in a file loaded from an Irb session
  class LoadAbort < Exception;end

  # Provides a few commands for loading files within an irb session.
  #
  # See ExtendCommandBundle for more information.
  module IrbLoader

    alias ruby_load load
    alias ruby_require require

    # Loads the given file similarly to Kernel#load
    def irb_load(fn, priv = nil)
      path = search_file_from_ruby_path(fn)
      raise LoadError, "No such file to load -- #{fn}" unless path

      load_file(path, priv)
    end

    def search_file_from_ruby_path(fn) # :nodoc:
      if File.absolute_path?(fn)
        return fn if File.exist?(fn)
        return nil
      end

      for path in $:
        if File.exist?(f = File.join(path, fn))
          return f
        end
      end
      return nil
    end

    # Loads a given file in the current session and displays the source lines
    #
    # See Irb#suspend_input_method for more information.
    def source_file(path)
      irb = irb_context.irb
      irb.suspend_name(path, File.basename(path)) do
        FileInputMethod.open(path) do |io|
          irb.suspend_input_method(io) do
            |back_io|
            irb.signal_status(:IN_LOAD) do
              if back_io.kind_of?(FileInputMethod)
                irb.eval_input
              else
                begin
                  irb.eval_input
                rescue LoadAbort
                  print "load abort!!\n"
                end
              end
            end
          end
        end
      end
    end

    # Loads the given file in the current session's context and evaluates it.
    #
    # See Irb#suspend_input_method for more information.
    def load_file(path, priv = nil)
      irb = irb_context.irb
      irb.suspend_name(path, File.basename(path)) do

        if priv
          ws = WorkSpace.new(Module.new)
        else
          ws = WorkSpace.new
        end
        irb.suspend_workspace(ws) do
          FileInputMethod.open(path) do |io|
            irb.suspend_input_method(io) do
              |back_io|
              irb.signal_status(:IN_LOAD) do
                if back_io.kind_of?(FileInputMethod)
                  irb.eval_input
                else
                  begin
                    irb.eval_input
                  rescue LoadAbort
                    print "load abort!!\n"
                  end
                end
              end
            end
          end
        end
      end
    end

    def old # :nodoc:
      back_io = @io
      back_path = irb_path
      back_name = @irb_name
      back_scanner = @irb.scanner
      begin
        @io = FileInputMethod.new(path)
        @irb_name = File.basename(path)
        self.irb_path = path
        @irb.signal_status(:IN_LOAD) do
          if back_io.kind_of?(FileInputMethod)
            @irb.eval_input
          else
            begin
              @irb.eval_input
            rescue LoadAbort
              print "load abort!!\n"
            end
          end
        end
      ensure
        @io = back_io
        @irb_name = back_name
        self.irb_path = back_path
        @irb.scanner = back_scanner
      end
    end
  end
end
