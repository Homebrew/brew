# typed: strict
# frozen_string_literal: true

module Homebrew
  module API
    module GeneratorMixin
      extend T::Helpers

      requires_ancestor { Kernel }

      PackageHash = T.type_alias { T::Hash[String, T.untyped] }

      module ClassMethods
        extend T::Helpers

        requires_ancestor { T.class_of(T::Struct) }

        BOTTLE_TAG_PLACEHOLDER = "@@BOTTLE_TAG_PLACEHOLDER@@"

        FromHashBlock = T.type_alias { T.proc.params(hash: PackageHash).returns(T.untyped) }

        class Property < T::Struct
          const :key, String
          const :type, T.anything
          const :hash_as, T.nilable(ClassMethods)
          const :default, T.anything
          const :from, T.nilable(T::Array[String])
          const :block, T.nilable(FromHashBlock)
        end

        sig { returns(T::Array[Property]) }
        def properties
          instance_variable_get(:@properties) || instance_variable_set(:@properties, [])
        end

        sig { returns(String) }
        def bottle_tag
          BOTTLE_TAG_PLACEHOLDER
        end

        sig {
          params(
            key:     Symbol,
            type:    T.anything,
            hash_as: T.nilable(ClassMethods),
            default: T.anything,
            from:    T.nilable(T.any(String, T::Array[String])),
            block:   T.nilable(FromHashBlock),
          ).void
        }
        def elem(key, type = nil, hash_as: nil, default: nil, from: nil, &block)
          raise ArgumentError, "Cannot specify both from: and a block for property #{key}" if from && block
          if [type, hash_as].compact.size != 1
            raise ArgumentError, "Must specify either a type or hash_as: for property #{key}"
          end

          type ||= hash_as
          from = Array(from) if from
          properties << Property.new(key: key.to_s, type:, hash_as:, default:, from:, block:)
          if default
            const key, type, default: default
          else
            const key, T.nilable(T.unsafe(type))
          end
        end

        sig { params(hash: PackageHash, bottle_tag: Utils::Bottles::Tag).returns(T.self_type) }
        def from_hash(hash, bottle_tag:)
          transformed_hash = properties.to_h do |property|
            source = if (block = property.block)
              block.call(hash)
            else
              from = property.from || [property.key]
              from.reduce(hash) do |h, key|
                key = bottle_tag.to_s if key == BOTTLE_TAG_PLACEHOLDER
                h[key] if h
              end
            end

            if source && (hash_class = property.hash_as)
              [property.key, hash_class.from_hash(source, bottle_tag:)]
            else
              [property.key, source]
            end
          end

          T.unsafe(self).new(**transformed_hash.compact_blank.transform_keys(&:to_sym))
        end
      end

      mixes_in_class_methods ClassMethods

      sig { returns(T::Hash[String, T.untyped]) }
      def to_h
        self.class.properties.to_h do |property|
          value = case (value = send(property.key.to_sym))
          when property.default || 0
            nil
          when GeneratorMixin
            value.to_h
          else
            # Other blank values are filtered out by compact_blank
            value
          end

          [property.key, value]
        end.to_h.compact_blank
      end

      sig { params(args: T.untyped).returns(String) }
      def to_json(*args)
        to_h.to_json(*args)
      end
    end
  end
end
