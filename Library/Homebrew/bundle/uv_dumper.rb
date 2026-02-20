# typed: strict
# frozen_string_literal: true

module Homebrew
  module Bundle
    module UvDumper
      sig { void }
      def self.reset!
        @packages = nil
      end

      sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def self.packages
        @packages ||= T.let(nil, T.nilable(T::Array[T::Hash[Symbol, T.untyped]]))
        @packages ||= if Bundle.uv_installed?
          uv = Bundle.which_uv
          output = `#{uv} tool list --show-version-specifiers --show-with --show-extras 2>/dev/null`
          parse_tool_list(output)
        else
          []
        end
      end

      sig { returns(String) }
      def self.dump
        packages.map do |package|
          build_entry(package)
        end.join("\n")
      end

      sig { params(output: String).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def self.parse_tool_list(output)
        entries = T.let([], T::Array[T::Hash[Symbol, T.untyped]])

        output.each_line do |line|
          match = line.match(/\A(\S+)\s+v\S+/)
          next unless match

          name = T.must(match[1])
          extras_raw = line[/\[extras:\s*([^\]]+)\]/, 1]
          name = name_with_extras(name, extras_raw)
          specifier = line[/\[required:\s*([^\]]+)\]/, 1]
          with_raw = line[/\[with:\s*([^\]]+)\]/, 1]

          with = parse_with_requirements(with_raw)

          entries << {
            name:      name,
            specifier: specifier,
            with:      with,
          }
        end

        entries.sort_by { |entry| T.cast(entry[:name], String) }
      end

      sig { params(name: String, extras_raw: T.nilable(String)).returns(String) }
      def self.name_with_extras(name, extras_raw)
        return name if extras_raw.blank?

        extras = extras_raw.split(",").map(&:strip).reject(&:empty?).uniq.sort
        return name if extras.empty?

        "#{name}[#{extras.join(",")}]"
      end

      sig { params(with_raw: T.nilable(String)).returns(T::Array[String]) }
      def self.parse_with_requirements(with_raw)
        return [] if with_raw.blank?

        entries = T.let([], T::Array[String])
        with_raw.split(", ").each do |token|
          requirement = token.strip
          next if requirement.empty?

          if continuation_constraint?(requirement) && entries.any?
            entries[-1] = "#{T.must(entries.last)}, #{normalize_constraint(requirement)}"
          else
            entries << requirement
          end
        end

        entries.uniq.sort
      end

      sig { params(requirement: String).returns(T::Boolean) }
      def self.continuation_constraint?(requirement)
        requirement.match?(/\A(?:<=|>=|!=|==|~=|<|>)\s*\S/)
      end

      sig { params(requirement: String).returns(String) }
      def self.normalize_constraint(requirement)
        requirement.strip.sub(/\A(<=|>=|!=|==|~=|<|>)\s+/, "\\1")
      end

      sig { params(package: T::Hash[Symbol, T.untyped]).returns(String) }
      def self.build_entry(package)
        name = T.cast(package[:name], String)
        specifier = T.cast(package[:specifier], T.nilable(String))
        with = T.cast(package[:with], T::Array[String])

        line = "uv #{quote(name)}"
        options = []
        options << "specifier: #{quote(specifier)}" if specifier.present?
        if with.present?
          formatted_with = with.map { |requirement| quote(requirement) }.join(", ")
          options << "with: [#{formatted_with}]"
        end
        return line if options.empty?

        "#{line}, #{options.join(", ")}"
      end

      sig { params(value: String).returns(String) }
      def self.quote(value)
        "\"#{value.gsub("\\", "\\\\").gsub("\"", "\\\"")}\""
      end
    end
  end
end
