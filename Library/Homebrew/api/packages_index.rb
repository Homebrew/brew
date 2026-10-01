# typed: strict
# frozen_string_literal: true

module Homebrew
  module API
    # Byte-offset index into a signature-verified internal packages JWS
    # payload, so commands can parse only the entries they need instead of
    # the whole multi-megabyte document.
    #
    # The index is derived, unverified cache data guarded in layers: the
    # payload bytes it points into are signature-verified on every run,
    # loading requires the recorded top-level spans to tile that payload
    # exactly (so the formulae and casks section spans are provably the
    # real top-level values) and every lookup revalidates that its offsets
    # sit at the expected `"<name>":` key inside the requested section's
    # span and that the slice parses. A forged or stale index therefore
    # cannot inject unverified content or remap a name to another entry,
    # even a matching key in the other section; it fails validation and
    # callers fall back to a full parse when {Invalid} is raised.
    class PackagesIndex
      FORMAT_VERSION = 1
      SECTION_KEYS = %w[formulae casks].freeze
      # Bounds index building when payload bytes stop round-tripping through
      # `JSON.generate`; giving up just means no index is written.
      MAX_FALSE_MATCH_RETRIES = 100

      # Raised when index contents do not match the verified payload.
      class Invalid < RuntimeError; end

      sig { params(target: Pathname).returns(Pathname) }
      def self.path_for(target)
        Pathname("#{target}.payload.index")
      end

      sig { params(stat: File::Stat).returns(T::Hash[String, Integer]) }
      def self.source_fingerprint(stat)
        {
          "source_size"     => stat.size,
          "source_mtime_ns" => (stat.mtime.to_r * 1_000_000_000).to_i,
        }
      end

      sig { params(target: Pathname, payload: String, source_stat: File::Stat).returns(T.nilable(PackagesIndex)) }
      def self.load(target, payload:, source_stat:)
        data = JSON.parse(path_for(target).read(encoding: Encoding::UTF_8))
        return unless data.is_a?(Hash)
        return if data["version"] != FORMAT_VERSION
        return if source_fingerprint(source_stat).any? { |key, value| data[key] != value }
        return if data["payload_bytesize"] != payload.bytesize

        top_level = data["top_level"]
        sections = data.slice(*SECTION_KEYS)
        return unless top_level.is_a?(Hash)
        return unless sections.values.all?(Hash)
        return unless top_level_spans_tile_payload?(payload, top_level)

        new(payload:, source_stat:, top_level:, sections:)
      rescue SystemCallError, JSON::ParserError
        nil
      end

      # The recorded top-level spans must reconstruct the payload's
      # top-level object exactly: starting at the opening brace, each span
      # is immediately preceded by its own comma-separated JSON key and the
      # last ends at the closing brace. This proves every span, including
      # the section spans entry lookups are bounded by, is the real
      # top-level value for its key rather than an arbitrary or inflated
      # byte range.
      sig { params(payload: String, top_level: T::Hash[String, T.untyped]).returns(T::Boolean) }
      private_class_method def self.top_level_spans_tile_payload?(payload, top_level)
        return false if payload.byteslice(0, 1) != "{"

        spans = top_level.map do |key, location|
          offset, bytesize = location
          return false if !offset.is_a?(Integer) || !bytesize.is_a?(Integer) || bytesize.negative?

          [key.to_s, offset, bytesize]
        end
        spans.sort_by! { |_, offset, _| offset }

        position = 1
        spans.each_with_index do |(key, offset, bytesize), index|
          key_bytes = "#{key.to_json}:"
          key_bytes = ",#{key_bytes}" if index.positive?
          return false if payload.byteslice(position, key_bytes.bytesize) != key_bytes
          return false if position + key_bytes.bytesize != offset

          position = offset + bytesize
        end

        position + 1 == payload.bytesize && payload.byteslice(position, 1) == "}"
      end

      # Builds and persists an index for a freshly verified and parsed
      # payload. Failing to build or write one only costs the fast path.
      sig {
        params(target: Pathname, payload: String, parsed: T::Hash[String, T.untyped],
               source_stat: File::Stat).void
      }
      def self.write!(target, payload:, parsed:, source_stat:)
        # Never write to a user-owned cache as root, matching `skip_download?`.
        return if Homebrew.running_as_root_but_not_owned_by_root?
        return if (data = build(payload:, parsed:)).nil?

        data = {
          "version"          => FORMAT_VERSION,
          **source_fingerprint(source_stat),
          "payload_bytesize" => payload.bytesize,
          **data,
        }
        index_path = path_for(target)
        temporary_path = Pathname("#{index_path}.tmp")
        begin
          temporary_path.write(JSON.generate(data))
          File.rename(temporary_path, index_path)
        ensure
          temporary_path.unlink if temporary_path.exist?
        end
      rescue SystemCallError
        nil
      end

      # Locates every top-level value and every formula and cask entry in the
      # payload bytes. Offsets are found by searching for each JSON key in
      # document order and validating that the following bytes byte-match the
      # entry's `JSON.generate` round trip, so every recorded offset provably
      # reproduces the canonical parse.
      sig {
        params(payload: String, parsed: T::Hash[String, T.untyped])
          .returns(T.nilable(T::Hash[String, T::Hash[String, [Integer, Integer]]]))
      }
      def self.build(payload:, parsed:)
        data = T.let({ "top_level" => {} }, T::Hash[String, T::Hash[String, [Integer, Integer]]])
        SECTION_KEYS.each { |section| data[section] = {} }
        retries = 0
        position = 0

        parsed.each do |key, value|
          location = locate(payload, key, value, position)
          return nil if location.nil?

          value_start, value_bytesize = location
          data.fetch("top_level")[key] = [value_start, value_bytesize]

          if SECTION_KEYS.include?(key) && value.is_a?(Hash)
            entry_position = value_start
            value.each do |name, entry|
              entry_location = T.let(nil, T.nilable([Integer, Integer]))
              loop do
                entry_location = locate(payload, name, entry, entry_position)
                break unless entry_location.nil?

                retries += 1
                return nil if retries > MAX_FALSE_MATCH_RETRIES

                next_position = payload.byteindex("#{name.to_json}:", entry_position)
                return nil if next_position.nil?

                entry_position = next_position + 1
              end

              entry_start, entry_bytesize = entry_location
              data.fetch(key)[name] = [entry_start, entry_bytesize]
              entry_position = entry_start + entry_bytesize
            end
          end

          position = value_start + value_bytesize
        end

        data
      end

      # Finds `"<key>":<value>` at or after `position`, returning the value's
      # byte offset and length only when the payload bytes match the value's
      # canonical serialisation exactly.
      sig {
        params(payload: String, key: String, value: T.untyped, position: Integer)
          .returns(T.nilable([Integer, Integer]))
      }
      private_class_method def self.locate(payload, key, value, position)
        key_bytes = "#{key.to_json}:"
        key_position = payload.byteindex(key_bytes, position)
        return if key_position.nil?

        value_bytes = JSON.generate(value)
        value_start = key_position + key_bytes.bytesize
        return if payload.byteslice(value_start, value_bytes.bytesize) != value_bytes

        [value_start, value_bytes.bytesize]
      end

      sig { returns(String) }
      attr_reader :payload

      sig { returns(File::Stat) }
      attr_reader :source_stat

      sig {
        params(payload: String, source_stat: File::Stat, top_level: T::Hash[String, T.untyped],
               sections: T::Hash[String, T::Hash[String, T.untyped]]).void
      }
      def initialize(payload:, source_stat:, top_level:, sections:)
        @payload = payload
        @source_stat = source_stat
        @top_level = top_level
        @sections = sections
      end

      sig { params(name: String).returns(T.nilable(T::Hash[String, T.untyped])) }
      def formula_hash(name)
        entry_value("formulae", name)
      end

      sig { params(name: String).returns(T.nilable(T::Hash[String, T.untyped])) }
      def cask_hash(name)
        entry_value("casks", name)
      end

      sig { returns(T::Array[String]) }
      def formula_names
        @sections.fetch("formulae", {}).keys
      end

      sig { returns(T::Array[String]) }
      def cask_names
        @sections.fetch("casks", {}).keys
      end

      sig { params(name: String).returns(T::Boolean) }
      def formula_name?(name)
        @sections.fetch("formulae", {}).key?(name)
      end

      sig { params(name: String).returns(T::Boolean) }
      def cask_name?(name)
        @sections.fetch("casks", {}).key?(name)
      end

      sig { params(key: String).returns(T.untyped) }
      def top_level_value(key)
        return if SECTION_KEYS.include?(key)

        location = @top_level[key]
        return if location.nil?

        slice_value(key, location)
      end

      private

      sig { params(section: String, name: String).returns(T.nilable(T::Hash[String, T.untyped])) }
      def entry_value(section, name)
        location = @sections.fetch(section, {})[name]
        return if location.nil?

        section_location = @top_level[section]
        raise Invalid, "no #{section} span for the #{name} index entry" unless section_location.is_a?(Array)

        value = slice_value(name, location, within: section_location)
        raise Invalid, "#{section} index entry for #{name} is not a hash" unless value.is_a?(Hash)

        value
      end

      # Revalidates a recorded location against the verified payload bytes:
      # it must be preceded by the expected JSON key, sit inside the given
      # load-validated span and parse cleanly.
      sig { params(name: String, location: T.untyped, within: T.untyped).returns(T.untyped) }
      def slice_value(name, location, within: nil)
        offset, bytesize = location
        key_bytes = "#{name.to_json}:"
        key_offset = offset - key_bytes.bytesize if offset.is_a?(Integer)
        if !offset.is_a?(Integer) || !bytesize.is_a?(Integer) ||
           key_offset.nil? || key_offset.negative? || (offset + bytesize) > payload.bytesize ||
           payload.byteslice(key_offset, key_bytes.bytesize) != key_bytes ||
           outside_span?(key_offset, offset + bytesize, within)
          raise Invalid, "index location for #{name} does not match the payload"
        end

        slice = payload.byteslice(offset, bytesize)
        raise Invalid, "index slice for #{name} is outside the payload" if slice.nil?

        begin
          JSON.parse(slice, freeze: true)
        rescue JSON::ParserError
          raise Invalid, "index slice for #{name} does not parse"
        end
      end

      sig { params(start_offset: Integer, end_offset: Integer, within: T.untyped).returns(T::Boolean) }
      def outside_span?(start_offset, end_offset, within)
        return false if within.nil?

        within_offset, within_bytesize = within
        return true if !within_offset.is_a?(Integer) || !within_bytesize.is_a?(Integer)

        start_offset < within_offset || end_offset > within_offset + within_bytesize
      end
    end
  end
end
