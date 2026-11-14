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
  class Timestamp
    TYPE = "timestamp"

    attr_reader :version, :spec_version, :expires, :snapshot_meta, :unrecognized_fields

    def initialize(data)
      type = data.fetch("_type")
      raise Error::InvalidData, "Expected type to be #{TYPE}, got #{type.inspect}" unless type == TYPE

      @version = data.fetch("version")
      @spec_version = data.fetch("spec_version")
      @expires = Time.iso8601 data.fetch("expires")
      meta_dict = data.fetch("meta")
      @snapshot_meta = Snapshot::Meta.from_hash(meta_dict["snapshot.json"])
      @unrecognized_fields = data.fetch("unrecognized_fields", {})
    end

    def expired?(reference_time)
      @expires < reference_time
    end
  end
end
