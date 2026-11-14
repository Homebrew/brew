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
  class Error < StandardError
    class InvalidSignature < Error; end
    class InvalidBundle < Error; end
    class InvalidCertificate < Error; end
    class NoCertificate < Error; end
    class NoTrustedRoot < Error; end
    class NoBundle < Error; end
    class NoSignature < Error; end
    class InvalidKey < Error; end
    class MissingLogId < Error; end
    class InvalidCheckpoint < Error; end
    class InvalidVerificationInput < Error; end

    class Signing < Error; end
    class InvalidIdentityToken < Error; end
    class InvalidSigningConfig < Error; end

    class InvalidTimestamp < Error; end

    class MissingRekorEntry < Error; end
    class InvalidRekorEntry < Error; end
    class FailedRekorLookup < Error; end
    class FailedRekorPost < Error; end

    class Unimplemented < Error; end

    class UnsupportedPlatform < Error; end
    class UnsupportedKeyType < Error; end
  end
end
