# typed: strict
# frozen_string_literal: true

class Hash
  # Returns a new hash with all keys converted by the block operation.
  # This includes the keys from the root hash and from all
  # nested hashes and arrays.
  #
  # ### Example
  #
  # ```ruby
  # hash = { person: { name: 'Rob', age: '28' } }
  #
  # hash.deep_transform_keys{ |key| key.to_s.upcase }
  # # => {"PERSON"=>{"NAME"=>"Rob", "AGE"=>"28"}}
  # ```
  def deep_transform_keys(&block) = _deep_transform_keys_in_object(self, &block)

  # Destructively converts all keys by using the block operation.
  # This includes the keys from the root hash and from all
  # nested hashes and arrays.
  def deep_transform_keys!(&block) = _deep_transform_keys_in_object!(self, &block)

  # Returns a new hash with all keys converted to strings.
  # This includes the keys from the root hash and from all
  # nested hashes and arrays.
  #
  # ### Example
  #
  # ```ruby
  # hash = { person: { name: 'Rob', age: '28' } }
  #
  # hash.deep_stringify_keys
  # # => {"person"=>{"name"=>"Rob", "age"=>"28"}}
  # ```
  def deep_stringify_keys
    deep_transform_keys do |key|
      case key
      when Object then key.to_s
      else raise TypeError, "Hash keys must be Objects"
      end
    end
  end

  # Returns a new hash with all keys converted to symbols, as long as
  # they respond to `to_sym`. This includes the keys from the root hash
  # and from all nested hashes and arrays.
  #
  # ### Example
  #
  # ```ruby
  # hash = { 'person' => { 'name' => 'Rob', 'age' => '28' } }
  #
  # hash.deep_symbolize_keys
  # # => {:person=>{:name=>"Rob", :age=>"28"}}
  # ```
  def deep_symbolize_keys
    deep_transform_keys do |key|
      case key
      when Object
        # `to_sym` is duck-typed rather than defined on `Object`.
        key.respond_to?(:to_sym) ? key.public_send(:to_sym) : key # rubocop:disable Style/SendWithLiteralMethodName
      else key
      end
    rescue
      key
    end
  end

  private

  # Support methods for deep transforming nested hashes and arrays.
  sig { params(object: T.anything, block: T.proc.params(k: T.untyped).returns(T.untyped)).returns(T.untyped) }
  def _deep_transform_keys_in_object(object, &block)
    case object
    when Hash
      object.each_with_object({}) do |(key, value), result|
        result[yield(key)] = _deep_transform_keys_in_object(value, &block)
      end
    when Array
      object.map { |e| _deep_transform_keys_in_object(e, &block) }
    else
      object
    end
  end

  sig { params(object: T.anything, block: T.proc.params(k: T.untyped).returns(T.untyped)).returns(T.untyped) }
  def _deep_transform_keys_in_object!(object, &block)
    case object
    when Hash
      # We can't use `each_key` here because we're updating the hash in-place.
      object.keys.each do |key|
        value = object.delete(key)
        object[yield(key)] = _deep_transform_keys_in_object!(value, &block)
      end
      object
    when Array
      object.map! { |e| _deep_transform_keys_in_object!(e, &block) }
    else
      object
    end
  end
end
