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

require_relative "../error"

module Sigstore::TUF
  class Error < ::Sigstore::Error
    # An error with a repository's state, such as a missing file.
    class RepositoryError < Error; end

    class LengthOrHashMismatch < RepositoryError; end
    class ExpiredMetadata < RepositoryError; end
    class BadVersionNumber < RepositoryError; end
    class EqualVersionNumber < BadVersionNumber; end
    class TooFewSignatures < RepositoryError; end

    class BadUpdateOrder < Error; end
    class InvalidData < Error; end
    class DuplicateKeys < Error; end

    # An error occurred while attempting to download a file.
    class DownloadError < Error; end

    class Fetch < Error; end
    class RemoteConnection < Fetch; end

    class UnsuccessfulResponse < Fetch
      attr_reader :response

      def initialize(message, response)
        super(message)
        @response = response
      end
    end
  end
end
