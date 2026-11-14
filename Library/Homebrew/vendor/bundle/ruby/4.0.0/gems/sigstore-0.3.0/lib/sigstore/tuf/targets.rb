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

require_relative "file"
require_relative "keys"
require_relative "roles"

module Sigstore::TUF
  class Targets
    TYPE = "targets"

    attr_reader :version, :targets, :delegations

    def initialize(data)
      type = data.fetch("_type")
      raise Error::InvalidData, "Expected type to be #{TYPE}, got #{type.inspect}" unless type == TYPE

      @version = data.fetch("version")
      @expires = Time.iso8601 data.fetch("expires")
      @targets = data.fetch("targets").to_h { |k, v| [k, Target.new(v, k)] }
      @delegations = Delegations.new(data.fetch("delegations", {}))

      @unrecognized_fields = data.fetch("unrecognized_fields", {})
    end

    def expired?(reference_time)
      @expires < reference_time
    end

    def verify_delegate(type, bytes, signatures)
      role = @delegations.fetch(type)
      role.verify_delegate(type, bytes, signatures)
    end

    class Target
      attr_reader :path, :hashes

      include BaseFile

      def initialize(data, path)
        @path = path
        @length = data.fetch("length")
        @hashes = data.fetch("hashes")
      end

      def verify_length_and_hashes(data)
        self.class.verify_length(data, @length)
        self.class.verify_hashes(data, @hashes)
      end
    end

    class Delegations
      def initialize(data)
        keys = Keys.new data.fetch("keys", {})
        @roles = Roles.new data.fetch("roles", []), keys
      end

      def roles_for_target(target_path)
        @roles.for_target(target_path)
      end

      def any?
        @roles.any?
      end

      def fetch(name)
        @roles.fetch(name)
      end
    end
  end
end
