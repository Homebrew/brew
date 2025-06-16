require 'bindata/base'
require 'bindata/dsl'

module BinData
  # A Choice is a collection of data objects of which only one is active
  # at any particular time.  Method calls will be delegated to the active
  # choice.
  #
  #   require 'bindata'
  #
  #   type1 = [:string, {value: "Type1"}]
  #   type2 = [:string, {value: "Type2"}]
  #
  #   choices = {5 => type1, 17 => type2}
  #   a = BinData::Choice.new(choices: choices, selection: 5)
  #   a # => "Type1"
  #
  #   choices = [ type1, type2 ]
  #   a = BinData::Choice.new(choices: choices, selection: 1)
  #   a # => "Type2"
  #
  #   choices = [ nil, nil, nil, type1, nil, type2 ]
  #   a = BinData::Choice.new(choices: choices, selection: 3)
  #   a # => "Type1"
  #
  #
  #   Chooser = Struct.new(:choice)
  #   mychoice = Chooser.new
  #   mychoice.choice = 'big'
  #
  #   choices = {'big' => :uint16be, 'little' => :uint16le}
  #   a = BinData::Choice.new(choices: choices, copy_on_change: true,
  #                           selection: -> { mychoice.choice })
  #   a.assign(256)
  #   a.to_binary_s #=> "\001\000"
  #
  #   mychoice.choice = 'little'
  #   a.to_binary_s #=> "\000\001"
  #
  # == Parameters
  #
  # Parameters may be provided at initialisation to control the behaviour of
  # an object.  These params are:
  #
  # <tt>:choices</tt>::        Either an array or a hash specifying the possible
  #                            data objects.  The format of the
  #                            array/hash.values is a list of symbols
  #                            representing the data object type.  If a choice
  #                            is to have params passed to it, then it should
  #                            be provided as [type_symbol, hash_params].  An
  #                            implementation constraint is that the hash may
  #                            not contain symbols as keys, with the exception
  #                            of :default.  :default is to be used when then
  #                            :selection does not exist in the :choices hash.
  # <tt>:selection</tt>::      An index/key into the :choices array/hash which
  #                            specifies the currently active choice.
  # <tt>:copy_on_change</tt>:: If set to true, copy the value of the previous
  #                            selection to the current selection whenever the
  #                            selection changes.  Default is false.
  class Choice < BinData::Base
    extend DSLMixin

    dsl_parser    :choice
    arg_processor :choice

    mandatory_parameters :choices, :selection
    optional_parameter   :copy_on_change

    def initialize_shared_instance
      extend CopyOnChangePlugin if eval_parameter(:copy_on_change) == true
      super
    end

    def initialize_instance
      @choices = {}
      @last_selection = nil
    end

    # Returns the current selection.
    def selection
      selection = eval_parameter(:selection)
      if selection.nil?
        raise IndexError, ":selection returned nil for #{debug_name}"
      end

      selection
    end

    def respond_to?(symbol, include_all = false) # :nodoc:
      current_choice.respond_to?(symbol, include_all) || super
    end

    def method_missing(symbol, *args, &block) # :nodoc:
      current_choice.__send__(symbol, *args, &block)
    end

    %w[clear? assign snapshot do_read do_write do_num_bytes].each do |m|
      module_eval <<-END
        def #{m}(*args)
          current_choice.#{m}(*args)
        end
      END
    end

    #---------------
    private

    def current_choice
      current_selection = selection
      @choices[current_selection] ||= instantiate_choice(current_selection)
    end

    def instantiate_choice(selection)
      prototype = get_parameter(:choices)[selection]
      if prototype.nil?
        msg = "selection '#{selection}' does not exist in :choices for #{debug_name}"
        raise IndexError, msg
      end

      prototype.instantiate(nil, self)
    end
  end

  class ChoiceArgProcessor < BaseArgProcessor
    def sanitize_parameters!(obj_class, params) # :nodoc:
      params.merge!(obj_class.dsl_params)

      params.sanitize_choices(:choices) do |choices|
        hash_choices = choices_as_hash(choices)
        ensure_valid_keys(hash_choices)
        hash_choices
      end
    end

    #-------------
    private

    def choices_as_hash(choices)
      if choices.respond_to?(:to_ary)
        key_array_by_index(choices.to_ary)
      else
        choices
      end
    end

    def key_array_by_index(array)
      result = {}
      array.each_with_index do |el, i|
        result[i] = el unless el.nil?
      end
      result
    end

    def ensure_valid_keys(choices)
      if choices.key?(nil)
        raise ArgumentError, ":choices hash may not have nil key"
      end
      if choices.keys.detect { |key| key.is_a?(Symbol) && key != :default }
        raise ArgumentError, ":choices hash may not have symbols for keys"
      end
    end
  end

  # Logic for the :copy_on_change parameter
  module CopyOnChangePlugin
    def current_choice
      obj = super
      copy_previous_value(obj)
      obj
    end

    def copy_previous_value(obj)
      current_selection = selection
      prev = get_previous_choice(current_selection)
      obj.assign(prev) unless prev.nil?
      remember_current_selection(current_selection)
    end

    def get_previous_choice(selection)
      if @last_selection && selection != @last_selection
        @choices[@last_selection]
      end
    end

    def remember_current_selection(selection)
      @last_selection = selection
    end
  end
end
