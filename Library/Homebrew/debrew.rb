# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

require "mutex_m"
require "ignorable"

# Helper module for debugging formulae.
module Debrew
  extend Mutex_m

  # Module for allowing to debug formulae.
  module Formula
    def install
      Debrew.debrew { super }
    end

    def patch
      Debrew.debrew { super }
    end

    def test
      Debrew.debrew { super }
    end
  end

  # Module for displaying a debugging menu.
  class Menu
    Entry = Struct.new(:name, :action)

    attr_accessor :prompt, :entries

    sig { void }
    def initialize
      @entries = []
    end

    def choice(name, &action)
      entries << Entry.new(name.to_s, action)
    end

    def self.choose
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

      choice[:action].call
    end
  end

  @active = false
  @debugged_exceptions = Set.new

  class << self
    attr_reader :debugged_exceptions

    sig { returns(T::Boolean) }
    def active? = @active
  end

  def self.debrew
    @active = true
    Ignorable.hook_raise

    begin
      yield
    rescue SystemExit
      raise
    rescue Ignorable::ExceptionMixin => e
      e.ignore if debug(e) == :ignore # execution jumps back to where the exception was thrown
    ensure
      Ignorable.unhook_raise
      @active = false
    end
  end

  def self.debug(exception)
    raise(exception) if !active? || !debugged_exceptions.add?(exception) || !mu_try_lock

    begin
      puts exception.backtrace.first
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
                  mu_synchronize do
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
      mu_unlock
    end
  end
end
