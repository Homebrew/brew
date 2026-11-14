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
  class << self
    attr_writer :logger

    def logger
      @logger ||= begin
        require "logger"
        Logger.new($stderr)
      end
    end
  end

  module Loggable
    def logger
      self.class.logger
    end

    def self.included(base)
      base.extend(ClassMethods)
    end

    module ClassMethods
      def logger
        Sigstore.logger
      end
    end
  end
end

require_relative "sigstore/signing_config"
require_relative "sigstore/verifier"
require_relative "sigstore/signer"
