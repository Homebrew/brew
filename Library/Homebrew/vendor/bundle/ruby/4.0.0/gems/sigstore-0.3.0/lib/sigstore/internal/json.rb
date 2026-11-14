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

module Sigstore::Internal
  module JSON
    # Implements https://wiki.laptop.org/go/Canonical_JSON
    #
    def self.canonical_generate(data, buffer = +"")
      case data
      when NilClass
        buffer << "null"
      when TrueClass
        buffer << "true"
      when FalseClass
        buffer << "false"
      when Integer
        buffer << data.to_s
      when String
        buffer << '"' << data.gsub(/(["\\])/, '\\\\\1') << '"'
      when Array
        buffer << "["
        data.each_with_index do |v, i|
          buffer << "," unless i.zero?
          canonical_generate(v, buffer)
        end
        buffer << "]"
      when Hash
        contents = data.sort_by do |k, _|
          raise ArgumentError, "Non-string key in hash" unless k.is_a?(String)

          k.encode("utf-16").codepoints
        end
        buffer << "{"
        comma = false
        contents.each do |k, v|
          if comma
            buffer << ","
          else
            comma = true
          end
          canonical_generate(k, buffer)
          buffer << ":"
          canonical_generate(v, buffer)
        end
        buffer << "}"
      else
        raise ArgumentError, "Unsupported data type: #{data.class}"
      end
    end
  end
end
