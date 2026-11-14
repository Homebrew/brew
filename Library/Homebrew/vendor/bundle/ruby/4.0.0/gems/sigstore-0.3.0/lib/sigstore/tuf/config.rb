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
  module TUF
    class UpdaterConfig
      attr_reader :max_root_rotations, :max_delegations, :root_max_length, :timestamp_max_length, :snapshot_max_length,
                  :targets_max_length, :prefix_targets_with_hash, :envelope_type, :app_user_agent

      def initialize(
        max_root_rotations: 32,
        max_delegations: 32,
        root_max_length: 512_000, # bytes
        timestamp_max_length: 16_384, # bytes
        snapshot_max_length: 2_000_000, # bytes
        targets_max_length: 5_000_000, # bytes
        prefix_targets_with_hash: true,
        envelope_type: :metadata,
        app_user_agent: nil
      )
        @max_root_rotations = max_root_rotations
        @max_delegations = max_delegations
        @root_max_length = root_max_length
        @timestamp_max_length = timestamp_max_length
        @snapshot_max_length = snapshot_max_length
        @targets_max_length = targets_max_length
        @prefix_targets_with_hash = prefix_targets_with_hash
        @envelope_type = envelope_type
        @app_user_agent = app_user_agent
      end
    end
  end
end
