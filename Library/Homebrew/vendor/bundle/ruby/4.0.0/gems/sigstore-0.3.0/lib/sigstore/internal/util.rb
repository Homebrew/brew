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
    module Util
      module_function

      def hash_algorithm_name(algorithm)
        case algorithm
        when Common::V1::HashAlgorithm::SHA2_256
          "sha256"
        when Common::V1::HashAlgorithm::SHA2_384
          "sha384"
        when Common::V1::HashAlgorithm::SHA2_512
          "sha512"
        else
          raise ArgumentError, "Unrecognized hash algorithm #{algorithm}"
        end
      end

      def hex_encode(string)
        string.unpack1("H*")
      end

      def hex_decode(string)
        [string].pack("H*")
      end

      def base64_encode(string)
        [string].pack("m0")
      end

      def base64_decode(string)
        string.unpack1("m0")
      end

      # The DSSE Pre-Authentication Encoding over a payload and its type, as
      # defined by the DSSE v1 spec. This is the byte string that is signed (and
      # verified) for a DSSE envelope.
      def dsse_pae(payload_type, payload)
        "DSSEv1 #{payload_type.bytesize} #{payload_type} #{payload.bytesize} #{payload}".b
      end
    end
  end
end
