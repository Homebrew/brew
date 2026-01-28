# frozen_string_literal: true
# typed: true

module T::Props
  # Helper to validate generated code, to mitigate security concerns around
  # `class_eval`. Not called by default; the expectation is this will be used
  # in a test iterating over all T::Props::Serializable subclasses.
  #
  # We validate the exact expected structure of the generated methods as far
  # as we can, and then where cloning produces an arbitrarily nested structure,
  # we just validate a lack of side effects.
  module GeneratedCodeValidation
    extend Private::Parse

    class ValidationError < RuntimeError; end

    def self.validate_deserialize(source)
      parsed = parse(source)

      # def %<name>(hash)
      #   ...
      # end
      assert_equal(:def, parsed.type)
      name, args, body = parsed.children
      assert_equal(:__t_props_generated_deserialize, name)
      assert_equal(s(:args, s(:arg, :hash)), args)

      assert_equal(:begin, body.type)
      init, *prop_clauses, ret = body.children

      # found = %<prop_count>
      # ...
      # found
      assert_equal(:lvasgn, init.type)
      init_name, init_val = init.children
      assert_equal(:found, init_name)
      assert_equal(:int, init_val.type)
      assert_equal(s(:lvar, :found), ret)

      prop_clauses.each_with_index do |clause, i|
        if i.even?
          validate_deserialize_hash_read(clause)
        else
          validate_deserialize_ivar_set(clause)
        end
      end
    end

    def self.validate_serialize(source)
      parsed = parse(source)

      # def %<name>(strict)
      # ...
      # end
      assert_equal(:def, parsed.type)
      name, args, body = parsed.children
      assert_equal(:__t_props_generated_serialize, name)
      assert_equal(s(:args, s(:arg, :strict)), args)

      assert_equal(:begin, body.type)
      init, *prop_clauses, ret = body.children

      # h = {}
      # ...
      # h
      assert_equal(s(:lvasgn, :h, s(:hash)), init)
      assert_equal(s(:lvar, :h), ret)

      prop_clauses.each do |clause|
        validate_serialize_clause(clause)
      end
    end

    private_class_method def self.validate_serialize_clause(clause)
      assert_equal(:if, clause.type)
      condition, if_body, else_body = clause.children

      # if @%<accessor_key>.nil?
      assert_equal(:send, condition.type)
      receiver, method = condition.children
      assert_equal(:ivar, receiver.type)
      assert_equal(:nil?, method)

      unless if_body.nil?
        # required_prop_missing_from_serialize(%<prop>) if strict
        assert_equal(:if, if_body.type)
        if_strict_condition, if_strict_body, if_strict_else = if_body.children
        assert_equal(s(:lvar, :strict), if_strict_condition)
        assert_equal(:send, if_strict_body.type)
        on_strict_receiver, on_strict_method, on_strict_arg = if_strict_body.children
        assert_equal(nil, on_strict_receiver)
        assert_equal(:required_prop_missing_from_serialize, on_strict_method)
        assert_equal(:sym, on_strict_arg.type)
        assert_equal(nil, if_strict_else)
      end

      # h[%<serialized_form>] = ...
      assert_equal(:send, else_body.type)
      receiver, method, h_key, h_val = else_body.children
      assert_equal(s(:lvar, :h), receiver)
      assert_equal(:[]=, method)
      assert_equal(:str, h_key.type)

      validate_lack_of_side_effects(h_val, whitelisted_methods_for_serialize)
    end

    private_class_method def self.validate_deserialize_hash_read(clause)
      # val = hash[%<serialized_form>s]

      assert_equal(:lvasgn, clause.type)
      name, val = clause.children
      assert_equal(:val, name)
      assert_equal(:send, val.type)
      receiver, method, arg = val.children
      assert_equal(s(:lvar, :hash), receiver)
      assert_equal(:[], method)
      assert_equal(:str, arg.type)
    end

    private_class_method def self.validate_deserialize_ivar_set(clause)
      # %<accessor_key>s = if val.nil?
      #   found -= 1 unless hash.key?(%<serialized_form>s)
      #   %<nil_handler>s
      # else
      #   %<serialized_val>s
      # end

      assert_equal(:ivasgn, clause.type)
      ivar_name, deser_val = clause.children
      unless ivar_name.is_a?(Symbol)
        raise ValidationError.new("Unexpected ivar: #{ivar_name}")
      end

      assert_equal(:if, deser_val.type)
      condition, if_body, else_body = deser_val.children
      assert_equal(s(:send, s(:lvar, :val), :nil?), condition)

      assert_equal(:begin, if_body.type)
      update_found, handle_nil = if_body.children
      assert_equal(:if, update_found.type)
      found_condition, found_if_body, found_else_body = update_found.children
      assert_equal(:send, found_condition.type)
      receiver, method, arg = found_condition.children
      assert_equal(s(:lvar, :hash), receiver)
      assert_equal(:key?, method)
      assert_equal(:str, arg.type)
      assert_equal(nil, found_if_body)
      assert_equal(s(:op_asgn, s(:lvasgn, :found), :-, s(:int, 1)), found_else_body)

      validate_deserialize_handle_nil(handle_nil)

      if else_body.type == :kwbegin
        rescue_expression, = else_body.children
        assert_equal(:rescue, rescue_expression.type)

        try, rescue_body = rescue_expression.children
        validate_lack_of_side_effects(try, whitelisted_methods_for_deserialize)

        assert_equal(:resbody, rescue_body.type)
        exceptions, assignment, handler = rescue_body.children
        assert_equal(:array, exceptions.type)
        exceptions.children.each { |c| assert_equal(:const, c.type) }
        assert_equal(:lvasgn, assignment.type)
        assert_equal([:e], assignment.children)

        deserialization_error, val_return = handler.children

        assert_equal(:send, deserialization_error.type)
        receiver, method, *args = deserialization_error.children
        assert_equal(nil, receiver)
        assert_equal(:raise_deserialization_error, method)
        args.each { |a| validate_lack_of_side_effects(a, whitelisted_methods_for_deserialize) }

        validate_lack_of_side_effects(val_return, whitelisted_methods_for_deserialize)
      else
        validate_lack_of_side_effects(else_body, whitelisted_methods_for_deserialize)
      end
    end

    private_class_method def self.validate_deserialize_handle_nil(node)
      case node.type
      when :hash, :array, :str, :sym, :int, :float, :true, :false, :nil, :const # rubocop:disable Lint/BooleanSymbol
        # Primitives and constants are safe
      when :send
        receiver, method, arg = node.children
        if receiver.nil?
          # required_prop_missing_from_deserialize(%<prop>)
          assert_equal(:required_prop_missing_from_deserialize, method)
          assert_equal(:sym, arg.type)
        elsif receiver == self_class_decorator
          # self.class.decorator.raise_nil_deserialize_error(%<serialized_form>)
          assert_equal(:raise_nil_deserialize_error, method)
          assert_equal(:str, arg.type)
        elsif method == :default
          # self.class.decorator.props_with_defaults.fetch(%<prop>).default
          assert_equal(:send, receiver.type)
          inner_receiver, inner_method, inner_arg = receiver.children
          assert_equal(
            s(:send, self_class_decorator, :props_with_defaults),
            inner_receiver,
          )
          assert_equal(:fetch, inner_method)
          assert_equal(:sym, inner_arg.type)
        else
          raise ValidationError.new("Unexpected receiver in nil handler: #{node.inspect}")
        end
      else
        raise ValidationError.new("Unexpected nil handler: #{node.inspect}")
      end
    end

    private_class_method def self.self_class_decorator
      @self_class_decorator ||= s(:send, s(:send, s(:self), :class), :decorator).freeze
    end

    private_class_method def self.validate_lack_of_side_effects(node, whitelisted_methods_by_receiver_type)
      case node.type
      when :const
        # This is ok, because we'll have validated what method has been called
        # if applicable
      when :hash, :array, :str, :sym, :int, :float, :true, :false, :nil, :self # rubocop:disable Lint/BooleanSymbol
        # Primitives & self are ok
      when :lvar, :arg, :ivar
        # Reading local & instance variables & arguments is ok
        unless node.children.all? { |c| c.is_a?(Symbol) }
          raise ValidationError.new("Unexpected child for #{node.type}: #{node.inspect}")
        end
      when :args, :mlhs, :block, :begin, :if
        # Blocks etc are read-only if their contents are read-only
        node.children.each { |c| validate_lack_of_side_effects(c, whitelisted_methods_by_receiver_type) if c }
      when :send
        # Sends are riskier so check a whitelist
        receiver, method, *args = node.children
        if receiver
          if receiver.type == :send
            key = receiver
          else
            key = receiver.type
            validate_lack_of_side_effects(receiver, whitelisted_methods_by_receiver_type)
          end

          if !whitelisted_methods_by_receiver_type[key]&.include?(method)
            raise ValidationError.new("Unexpected method #{method} called on #{receiver.inspect}")
          end
        end
        args.each do |arg|
          validate_lack_of_side_effects(arg, whitelisted_methods_by_receiver_type)
        end
      else
        raise ValidationError.new("Unexpected node type #{node.type}: #{node.inspect}")
      end
    end

    private_class_method def self.assert_equal(expected, actual)
      if expected != actual
        raise ValidationError.new("Expected #{expected}, got #{actual}")
      end
    end

    # Method calls generated by SerdeTransform
    private_class_method def self.whitelisted_methods_for_serialize
      @whitelisted_methods_for_serialize ||= {
        lvar: %i{dup map transform_values transform_keys each_with_object nil? []= serialize},
        ivar: %i[dup map transform_values transform_keys each_with_object serialize],
        const: %i[checked_serialize deep_clone_object],
      }
    end

    # Method calls generated by SerdeTransform
    private_class_method def self.whitelisted_methods_for_deserialize
      @whitelisted_methods_for_deserialize ||= {
        lvar: %i{dup map transform_values transform_keys each_with_object nil? []= to_f},
        const: %i[deserialize from_hash deep_clone_object],
      }
    end
  end
end
