# typed: strict
# frozen_string_literal: true

require "ignorable"

# Helper module for debugging formulae.
module Debrew
  # Module for allowing to debug formulae.
  module Formula
    sig { void }
    def install
      Debrew.debrew { super }
    end

    sig { void }
    def patch
      Debrew.debrew { super }
    end

    sig {
      # TODO: replace `returns(BasicObject)` with `void` after dropping `return false` handling in test
      returns(BasicObject)
    }
    def test
      Debrew.debrew { super }
    end
  end

  # Module for displaying a debugging menu.
  class Menu
    class Entry < T::Struct
      const :name, String
      const :action, T.proc.void
    end

    sig { returns(T.nilable(String)) }
    attr_accessor :prompt

    sig { returns(T::Array[Entry]) }
    attr_accessor :entries

    sig { void }
    def initialize
      @entries = T.let([], T::Array[Entry])
    end

    sig { params(name: Symbol, action: T.proc.void).void }
    def choice(name, &action)
      entries << Entry.new(name: name.to_s, action:)
    end

    sig { params(_block: T.proc.params(menu: Menu).void).void }
    def self.choose(&_block)
      menu = new
      yield menu

      choice = T.let(nil, T.nilable(Entry))
      while choice.nil?
        menu.entries.each_with_index { |e, i| puts "#{i + 1}. #{e.name}" }
        print menu.prompt unless menu.prompt.nil?

        input = $stdin.gets || exit
        input.chomp!

        i = input.to_i
        if i.positive?
          choice = menu.entries[i - 1]
        else
          possible = menu.entries.select { |e| e.name.start_with?(input) }

          case possible.size
          when 0 then puts "No such option"
          when 1 then choice = possible.first
          else puts "Multiple options match: #{possible.map(&:name).join(" ")}"
          end
        end
      end

      choice.action.call
    end
  end

  @mutex = T.let(nil, T.nilable(Mutex))
  @debugged_exceptions = T.let(Set.new, T::Set[Exception])

  class << self
    sig { returns(T::Set[Exception]) }
    attr_reader :debugged_exceptions

    sig { returns(T::Boolean) }
    def active? = !@mutex.nil?
  end

  sig {
    type_parameters(:U)
      .params(_block: T.proc.returns(T.type_parameter(:U)))
      .returns(T.type_parameter(:U))
  }
  def self.debrew(&_block)
    @mutex = Mutex.new
    Ignorable.hook_raise

    begin
      yield
    rescue SystemExit
      raise
    rescue Ignorable::ExceptionMixin => e
      e.ignore if debug(e) == :ignore # execution jumps back to where the exception was thrown
    ensure
      Ignorable.unhook_raise
      @mutex = nil
    end
  end

  sig { params(exception: Exception).returns(Symbol) }
  def self.debug(exception)
    raise(exception) if !active? || !debugged_exceptions.add?(exception) || !@mutex&.try_lock

    begin
      puts exception.backtrace&.first
      puts Formatter.error(exception, label: exception.class.name)

      loop do
        Menu.choose do |menu|
          menu.prompt = "Choose an action: "

          menu.choice(:raise) { raise(exception) }
          menu.choice(:ignore) { return :ignore } if exception.is_a?(Ignorable::ExceptionMixin)
          menu.choice(:backtrace) { puts exception.backtrace }

          if exception.is_a?(Ignorable::ExceptionMixin)
            menu.choice(:irb) do
              puts "When you exit this IRB session, execution will continue."
              set_trace_func proc { |event, _, _, id, binding, klass|
                if klass == Object && id == :raise && event == "return"
                  set_trace_func(nil)
                  @mutex.synchronize do
                    require "debrew/irb"
                    IRB.start_within(binding)
                  end
                end
              }

              return :ignore
            end
          end

          menu.choice(:shell) do
            puts "When you exit this shell, you will return to the menu."
            interactive_shell
          end
        end
      end
    ensure
      @mutex.unlock
    end
  end
end
