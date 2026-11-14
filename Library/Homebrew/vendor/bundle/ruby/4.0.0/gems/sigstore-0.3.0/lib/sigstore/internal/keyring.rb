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

module Sigstore
  module Internal
    class Keyring
      def initialize(keys:)
        @keyring = {}
        keys.each do |key|
          raise Error, "Duplicate key id #{key.key_id} in keyring" if @keyring.key?(key.key_id)

          @keyring[key.key_id] = key
        end
      end

      def verify(key_id:, signature:, data:)
        key = @keyring.fetch(key_id) { raise KeyError, "key not found: #{key_id.inspect}, known: #{@keyring.keys}" }

        return true if key.verify("SHA256", signature, data)

        raise(Error::InvalidSignature,
              "invalid signature: #{signature.inspect} over #{data.inspect} with key #{key_id.inspect}")
      rescue OpenSSL::PKey::PKeyError => e
        raise(Error::InvalidSignature,
              "#{e}: invalid signature: #{signature.inspect} over #{data.inspect} with key #{key_id.inspect}")
      end
    end
  end
end
