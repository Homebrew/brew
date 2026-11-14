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

module Sigstore::TUF
  class Keys
    include Enumerable

    def initialize(keys)
      @keys = keys.to_h do |key_id, key_data|
        key_type = key_data.fetch("keytype")
        scheme = key_data.fetch("scheme")
        keyval = key_data.fetch("keyval")
        public_key_data = keyval.fetch("public")

        key = Sigstore::Internal::Key.read(key_type, scheme, public_key_data, key_id:)

        [key_id, key]
      end
    end

    def fetch(key_id)
      @keys.fetch(key_id)
    end

    def each(&)
      @keys.each(&)
    end
  end
end
