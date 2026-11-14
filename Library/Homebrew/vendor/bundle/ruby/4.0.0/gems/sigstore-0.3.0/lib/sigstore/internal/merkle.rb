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

require_relative "util"

module Sigstore
  module Internal
    module Merkle
      class MissingInclusionProofError < StandardError; end
      class MissingHashError < StandardError; end
      class InvalidInclusionProofError < StandardError; end
      class InclusionProofSizeError < InvalidInclusionProofError; end

      def self.verify_merkle_inclusion(entry)
        inclusion_proof = entry.inclusion_proof
        raise MissingInclusionProofError, "Rekor entry has no inclusion proof" unless inclusion_proof

        leaf_hash = hash_leaf(entry.canonicalized_body)
        verify_inclusion(inclusion_proof.log_index, inclusion_proof.tree_size,
                         inclusion_proof.hashes,
                         inclusion_proof.root_hash, leaf_hash)
      end

      def self.verify_inclusion(index, tree_size, proof, root, leaf_hash)
        calc_hash = root_from_inclusion_proof(index, tree_size, proof, leaf_hash)

        return if calc_hash == root

        raise InvalidInclusionProofError,
              "Inclusion proof contains invalid root hash: " \
              "expected #{root.unpack1("H*")}, calculated #{calc_hash.unpack1("H*")}"
      end

      def self.root_from_inclusion_proof(log_index, tree_size, proof, leaf_hash)
        if log_index >= tree_size
          raise InclusionProofSizeError,
                "Log index #{log_index} is greater than tree size #{tree_size}"
        end

        if leaf_hash.bytesize != 32
          raise InvalidInclusionProofError,
                "Leaf hash has wrong size, expected 32 bytes, got #{leaf_hash.size}"
        end

        if proof.any? { |i| i.bytesize != 32 }
          raise InvalidInclusionProofError,
                "Proof hashes have wrong sizes, expected 32 bytes, got #{proof.inspect}"
        end

        inner, border = decompose_inclusion_proof(log_index, tree_size)

        if proof.size != inner + border
          raise InclusionProofSizeError,
                "Inclusion proof has wrong size, expected #{inner + border} hashes, got #{proof.size}"
        end

        intermediate_result = chain_inner(
          leaf_hash,
          proof[...inner] || raise(MissingHashError, "missing left hashes"),
          log_index
        )

        chain_border_right(
          intermediate_result,
          proof[inner..] || raise(MissingHashError, "missing right hashes")
        )
      end

      def self.decompose_inclusion_proof(log_index, tree_size)
        inner = (log_index ^ (tree_size - 1)).bit_length
        border = (log_index >> inner).to_s(2).count("1")

        [inner, border]
      end

      def self.hash_leaf(data)
        data = "\u0000#{data}".b
        OpenSSL::Digest.new("SHA256").digest(data)
      end

      def self.chain_inner(seed, hashes, log_index)
        hashes.each_with_index do |hash, i|
          seed = if (log_index >> i).nobits?(1)
                   hash_children(seed, hash)
                 else
                   hash_children(hash, seed)
                 end
        end
        seed
      end

      def self.chain_border_right(seed, hashes)
        hashes.reduce(seed) do |acc, hash|
          hash_children(hash, acc)
        end
      end

      def self.hash_children(left, right)
        data = "\u0001#{left}#{right}".b
        OpenSSL::Digest.new("SHA256").digest(data)
      end
    end
  end
end
