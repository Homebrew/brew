# frozen_string_literal: true

require "rbs"
require "pp"

module RBS
  module Test
    module Hook
      OPERATORS = {
        :[] => "indexlookup",
        :[]= => "indexset",
        :== => "eqeq",
        :=== => "eqeqeq",
        :!= => "noteq",
        :+ => "plus",
        :- => "minus",
        :* => "star",
        :/ => "slash",
        :> => "gt",
        :>= => "gteq",
        :< => "lt",
        :<= => "lteq",
        :<=> => "ufo",
        :& => "amp",
        :| => "vbar",
        :^ => "hat",
        :! => "not",
        :<< => "lshift",
        :>> => "rshift",
        :~ => "tilda",
        :=~ => "eqtilda",
        :% => "percent",
        :+@ => "unary_plus",
        :-@ => "unary_minus"
      }
      def self.alias_names(target, random)
        suffix = "#{RBS::Test.suffix}_#{random}"

        case target
        when *OPERATORS.keys
          name = OPERATORS[target]
          [
            "#{name}____with__#{suffix}",
            "#{name}____without__#{suffix}"
          ]
        else
          aliased_target, punctuation = target.to_s.sub(/([?!=])$/, ''), $1

          [
            "#{aliased_target}__with__#{suffix}#{punctuation}",
            "#{aliased_target}__without__#{suffix}#{punctuation}"
          ]
        end
      end

      def self.setup_alias_method_chain(klass, target, random:)
        with_method, without_method = alias_names(target, random)

        RBS.logger.debug "alias name: #{target}, #{with_method}, #{without_method}"

        klass.instance_eval do
          alias_method without_method, target
          alias_method target, with_method

          case
          when public_method_defined?(without_method)
            public target
          when protected_method_defined?(without_method)
            protected target
          when private_method_defined?(without_method)
            private target
          end
        end
      end

      def self.hook_method_source(prefix, method_name, key, random:, params:)
        with_name, without_name = alias_names(method_name, random)
        full_method_name = "#{prefix}#{method_name}"

        param_source = params.take_while {|param| param[0] == :req }
                             .map.with_index {|pair, index| pair[1] || "__req__#{random}__#{index}" }
        param_source.push("*rest_args__#{random}")
        block_param = "block__#{random}"

        RBS.logger.debug {
          "Generating method definition: def #{with_name}(#{param_source.join(", ")}, &#{block_param}) ..."
        }

        [__LINE__ + 1, <<RUBY]
def #{with_name}(#{param_source.join(", ")}, &#{block_param})
  args = [#{param_source.join(", ")}]
  ::RBS.logger.debug { "#{full_method_name} with arguments: [" + args.map(&:inspect).join(", ") + "]" }

  begin
    return_from_call = false
    block_calls = []

    if block_given?
      receiver = self
      block_receives_block = #{block_param}.parameters.last&.yield_self {|type, _| type == :block }

      wrapped_block = proc do |*block_args, &block2|
        return_from_block = false

        begin
          block_result = if receiver.equal?(self)
                           if block_receives_block
                             #{block_param}.call(*block_args, &block2)
                           else
                             yield(*block_args)
                           end
                         else
                           instance_exec(*block_args, &#{block_param})
                         end

          return_from_block = true
        ensure
          exn = $!

          case
          when return_from_block
            # Returned from yield
            block_calls << ::RBS::Test::ArgumentsReturn.return(
              arguments: block_args,
              value: block_result
            )
          when exn
            # Exception
            block_calls << ::RBS::Test::ArgumentsReturn.exception(
              arguments: block_args,
              exception: exn
            )
          else
            # break?
            block_calls << ::RBS::Test::ArgumentsReturn.break(
              arguments: block_args
            )
          end
        end

        block_result
      end.ruby2_keywords

      result = __send__(:"#{without_name}", *args, &wrapped_block)
    else
      result = __send__(:"#{without_name}", *args)
    end
    return_from_call = true
    result
  ensure
    exn = $!

    case
    when return_from_call
      ::RBS.logger.debug { "#{full_method_name} return with value: " + result.inspect }
      method_call = ::RBS::Test::ArgumentsReturn.return(
        arguments: args,
        value: result
      )
    when exn
      ::RBS.logger.debug { "#{full_method_name} exit with exception: " + exn.inspect }
      method_call = ::RBS::Test::ArgumentsReturn.exception(
        arguments: args,
        exception: exn
      )
    else
      ::RBS.logger.debug { "#{full_method_name} exit with jump" }
      method_call = ::RBS::Test::ArgumentsReturn.break(arguments: args)
    end

    trace = ::RBS::Test::CallTrace.new(
      method_name: #{method_name.inspect},
      method_call: method_call,
      block_calls: block_calls,
      block_given: block_given?,
    )

    ::RBS::Test::Observer.notify(#{key.inspect}, self, trace)
  end

  result
end

ruby2_keywords :#{with_name}
RUBY
      end

      def self.hook_instance_method(klass, method, key:)
        random = SecureRandom.hex(4)
        params = klass.instance_method(method).parameters
        line, source = hook_method_source("#{klass}#", method, key, random: random, params: params)

        klass.module_eval(source, __FILE__, line)
        setup_alias_method_chain klass, method, random: random
      end

      def self.hook_singleton_method(klass, method, key:)
        random = SecureRandom.hex(4)
        params = klass.method(method).parameters
        line, source = hook_method_source("#{klass}.",method, key, random: random, params: params)

        klass.singleton_class.module_eval(source, __FILE__, line)
        setup_alias_method_chain klass.singleton_class, method, random: random
      end
    end
  end
end
