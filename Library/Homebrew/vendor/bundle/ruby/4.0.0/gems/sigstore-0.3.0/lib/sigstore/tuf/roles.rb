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
  class Roles
    include Enumerable

    def initialize(data, keys)
      @roles =
        case data
        when Hash # root roles
          data.to_h do |role_name, role_data|
            role_data = role_data.merge("name" => role_name, "paths" => nil)
            role = Role.new(role_data, keys)
            [role.name, role]
          end
        when Array # targets roles
          data.to_h do |role_data|
            role = Role.new(role_data, keys)
            [role.name, role]
          end
        else
          raise ArgumentError, "Unexpected data: #{data.inspect}"
        end
    end

    def each(&)
      @roles.each(&)
    end

    def verify_delegate(type, bytes, signatures)
      role = fetch(type)
      role.verify_delegate(type, bytes, signatures)
    end

    def fetch(name)
      @roles.fetch(name)
    end

    def for_target(target_path)
      select do |_, role|
        # TODO: this needs to be tested
        role.paths.any? { |path| File.fnmatch?(path, target_path, File::FNM_PATHNAME) }
      end.to_h
    end
  end

  class Role
    include Sigstore::Loggable

    attr_reader :keys, :name, :paths, :threshold

    def initialize(data, keys)
      @name = data.fetch("name")
      @paths = data.fetch("paths")
      @threshold = data.fetch("threshold")
      @keys = data.fetch("keyids").to_h { |key_id| [key_id, keys.fetch(key_id)] }
      @terminating = data.fetch("terminating", false)
    end

    def terminating?
      @terminating
    end

    def verify_delegate(type, bytes, signatures)
      if (duplicate_keys = signatures.map { |sig| sig.fetch("keyid") }.tally.select { |_, count| count > 1 }).any?
        raise Error::DuplicateKeys, "Duplicate keys found in signatures: #{duplicate_keys.inspect}"
      end

      count = signatures.count do |signature|
        key_id = signature.fetch("keyid")
        unless @keys.include?(key_id)
          logger.warn "Unknown key_id=#{key_id.inspect} in signatures for #{type}"
          next
        end

        key = @keys.fetch(key_id)
        signature_bytes = [signature.fetch("sig")].pack("H*")
        verified = key.verify("sha256", signature_bytes, bytes)

        logger.debug do
          "key_id=#{key_id.inspect} type=#{type} verified=#{verified}"
        end
        verified
      end

      return unless count < @threshold

      raise Error::TooFewSignatures,
            "Not enough signatures: found #{count} out of threshold=#{@threshold} for #{type}"
    end
  end
end
