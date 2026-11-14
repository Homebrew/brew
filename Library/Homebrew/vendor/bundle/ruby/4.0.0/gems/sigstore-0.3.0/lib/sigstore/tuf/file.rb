# frozen_string_literal: true

# Copyright 2024 The Sigstore Authors
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require_relative "error"

module Sigstore::TUF
  module BaseFile
    def self.included(base)
      base.extend(ClassMethods)
      super
    end

    module ClassMethods
      def verify_hashes(data, expected_hashed)
        expected_hashed.each do |algorithm, expected_hash|
          actual_hash = Digest(algorithm.upcase).hexdigest(data)
          unless actual_hash == expected_hash
            raise Error::LengthOrHashMismatch,
                  "observed hash #{actual_hash} does not match expected hash #{expected_hash}"
          end
        end
      end

      def verify_length(data, expected_length)
        actual_length = data.bytesize
        return if actual_length == expected_length

        raise Error::LengthOrHashMismatch,
              "Observed length #{actual_length} does not match expected length #{expected_length}"
      end

      def validate_hashes(hashes)
        raise ArgumentError, "hashes must be non-empty" if hashes.empty?

        hashes.each do |algorithm, hash|
          raise TypeError, "hashes items must be strings" unless algorithm.is_a?(String) && hash.is_a?(String)
        end
      end

      def validate_length(length)
        return unless length.negative?

        raise ArgumentError, "length must be a non-negative integer, got #{length.inspect}"
      end
    end
  end

  module MetaFile
    def self.included(base)
      base.include(BaseFile)
      base.extend(ClassMethods)
      super
    end

    def initialize(version: 1, length: nil, hashes: nil, unrecognized_fields: {})
      @version = version
      @length = length
      @hashes = hashes
      @unrecognized_fields = unrecognized_fields

      raise ArgumentError, "Metafile version must be positive, got #{@version}" if @version <= 0

      self.class.validate_length(@length) unless @length.nil?
      self.class.validate_hashes(@hashes) unless @hashes.nil?
    end

    def verify_length_and_hashes(data)
      self.class.verify_length(data, @length) if @length
      self.class.verify_hashes(data, @hashes) if @hashes
    end

    module ClassMethods
      def from_hash(meta_dict)
        version = meta_dict.fetch("version") { raise KeyError, "version is required, given #{meta_dict.inspect}" }
        length = meta_dict.fetch("length", nil)
        hashes = meta_dict.fetch("hashes", nil)

        new(version:, length:, hashes:,
            unrecognized_fields: meta_dict.slice(*(meta_dict.keys - %w[version length hashes])))
      end
    end
  end
end
