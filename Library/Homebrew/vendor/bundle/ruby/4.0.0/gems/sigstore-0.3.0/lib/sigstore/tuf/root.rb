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

require "time"

require_relative "keys"
require_relative "roles"
require_relative "../internal/key"

module Sigstore::TUF
  class Root
    include Sigstore::Loggable

    TYPE = "root"
    attr_reader :version, :consistent_snapshot, :expires

    def initialize(data)
      type = data.fetch("_type")
      raise Error::InvalidData, "Expected type to be #{TYPE}, got #{type.inspect}" unless type == TYPE

      @spec_version = data.fetch("spec_version") { raise Error::InvalidData, "root missing spec_version" }
      @consistent_snapshot = data.fetch("consistent_snapshot") do
        raise Error::InvalidData, "root missing consistent_snapshot"
      end
      @version = data.fetch("version") { raise Error::InvalidData, "root missing version" }
      @expires = Time.iso8601(data.fetch("expires") { raise Error::InvalidData, "root missing expires" })
      keys = Keys.new data.fetch("keys")
      @roles = Roles.new data.fetch("roles"), keys
      @unrecognized_fields = data.fetch("unrecognized_fields", {})
    end

    def verify_delegate(type, bytes, signatures)
      @roles.verify_delegate(type, bytes, signatures)
    end

    def expired?(reference_time)
      @expires < reference_time
    end
  end
end
