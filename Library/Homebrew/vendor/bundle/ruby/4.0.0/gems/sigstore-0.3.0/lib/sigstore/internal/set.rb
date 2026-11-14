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
    module SET
      def self.verify_set(keyring:, entry:)
        raise Error, "invalid log entry: no inclusion promise" unless entry.inclusion_promise

        signed_entry_timestamp = entry.inclusion_promise.signed_entry_timestamp
        log_id = Util.hex_encode(entry.log_id.key_id)

        # https://www.rfc-editor.org/rfc/rfc8785
        canonical_entry = ::JSON.dump({
                                        body: Internal::Util.base64_encode(entry.canonicalized_body),
                                        integratedTime: entry.integrated_time,
                                        logID: log_id,
                                        logIndex: entry.log_index
                                      })

        keyring.verify(
          key_id: log_id,
          signature: signed_entry_timestamp,
          data: canonical_entry
        )
      end
    end
  end
end
