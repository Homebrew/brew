# typed: strict
# frozen_string_literal: true

require "bundle/extensions/extension"

module Homebrew
  module Bundle
    class Uv < Extension
      WithOptions = T.type_alias { T::Hash[Symbol, T::Array[String]] }
      Tool = T.type_alias { { name: String, with: T::Array[String] } }
      Checkable = T.type_alias { { name: String, options: WithOptions } }
      ToolEntry = T.type_alias { T.any(Tool, Checkable) }

      PACKAGE_TYPE = :uv
      PACKAGE_TYPE_NAME = "uv Tool"
      BANNER_NAME = "uv tools"

      class << self
        sig { override.params(name: String, options: Homebrew::Bundle::EntryInputOptions).returns(Dsl::Entry) }
        def entry(name, options = {})
          unknown_options = options.keys - [:with]
          raise "unknown options(#{unknown_options.inspect}) for uv" if unknown_options.present?

          with = options[:with]
          if !with.nil? && (!with.is_a?(Array) || with.any? { |requirement| !requirement.is_a?(String) })
            raise "options[:with](#{with.inspect}) should be an Array of String objects"
          end

          normalized_options = {}
          normalized_with = normalize_with(with || [])
          normalized_options[:with] = normalized_with if normalized_with.present?

          Dsl::Entry.new(:uv, name, normalized_options)
        end

        sig { override.void }
        def reset!
          @packages = T.let(nil, T.nilable(T::Array[Tool]))
          @installed_packages = T.let(nil, T.nilable(T::Array[Tool]))
        end

        sig { override.returns(T.nilable(String)) }
        def cleanup_heading
          banner_name
        end

        sig { override.returns(T::Array[Tool]) }
        def packages
          packages = @packages
          return packages if packages

          @packages = if (uv = package_manager_executable)
            output = `#{uv} tool list --show-with --show-extras 2>/dev/null`
            parse_tool_list(output)
          end
          return [] if @packages.nil?

          @packages
        end

        sig { override.params(package: Object).returns(String) }
        def dump_name(package)
          package_name(T.cast(package, ToolEntry))
        end

        sig { override.params(package: Object).returns(T.nilable(T::Array[String])) }
        def dump_with(package)
          package_with(T.cast(package, ToolEntry))
        end

        sig {
          override.params(
            name:    String,
            with:    T.nilable(T::Array[String]),
            verbose: T::Boolean,
          ).returns(T::Boolean)
        }
        def install_package!(name, with: nil, verbose: false)
          uv = package_manager_executable!

          args = ["tool", "install", name]
          normalize_with(with || []).each do |requirement|
            args << "--with"
            args << requirement
          end

          Bundle.system(uv.to_s, *args, verbose:)
        end

        sig { override.returns(T::Array[Tool]) }
        def installed_packages
          installed_packages = @installed_packages
          return installed_packages if installed_packages

          @installed_packages = packages.dup
        end

        sig { params(output: String).returns(T::Array[Tool]) }
        def parse_tool_list(output)
          entries = T.let([], T::Array[Tool])

          output.each_line do |line|
            match = line.match(/\A(\S+)\s+v\S+/)
            next unless match

            name = match[1]
            next if name.nil?

            extras_raw = line[/\[extras:\s*([^\]]+)\]/, 1]
            name = name_with_extras(name, extras_raw)
            with_raw = line[/\[with:\s*([^\]]+)\]/, 1]

            entries << {
              name: name,
              with: parse_with_requirements(with_raw),
            }
          end

          entries.sort_by { |entry| entry[:name].to_s }
        end
        private :parse_tool_list

        sig { params(name: String, extras_raw: T.nilable(String)).returns(String) }
        def name_with_extras(name, extras_raw)
          return name if extras_raw.blank?

          extras = extras_raw.split(",").map(&:strip).reject(&:empty?).uniq.sort
          return name if extras.empty?

          "#{name}[#{extras.join(",")}]"
        end
        private :name_with_extras

        sig { params(with_raw: T.nilable(String)).returns(T::Array[String]) }
        def parse_with_requirements(with_raw)
          return [] if with_raw.blank?

          entries = T.let([], T::Array[String])
          with_raw.split(", ").each do |token|
            requirement = token.strip
            next if requirement.empty?

            if continuation_constraint?(requirement) && entries.any?
              last_requirement = entries.pop
              entries << "#{last_requirement}, #{normalize_constraint(requirement)}" if last_requirement
            else
              entries << requirement
            end
          end

          entries.uniq.sort
        end
        private :parse_with_requirements

        sig { params(requirement: String).returns(T::Boolean) }
        def continuation_constraint?(requirement)
          requirement.match?(/\A(?:<=|>=|!=|==|~=|<|>)\s*\S/)
        end
        private :continuation_constraint?

        sig { params(requirement: String).returns(String) }
        def normalize_constraint(requirement)
          requirement.strip.sub(/\A(<=|>=|!=|==|~=|<|>)\s+/, "\\1")
        end
        private :normalize_constraint

        sig { params(with: T::Array[String]).returns(T::Array[String]) }
        def normalize_with(with)
          with.map(&:strip).reject(&:empty?).uniq.sort
        end
        private :normalize_with

        sig { params(name: String).returns(String) }
        def normalize_name(name)
          match = name.strip.match(/\A(?<base>[^\[\]]+)(?:\[(?<extras>[^\]]+)\])?\z/)
          return name.strip unless match

          base = match[:base]
          return name.strip if base.nil?

          extras_raw = match[:extras]
          return base.strip if extras_raw.blank?

          extras = extras_raw.split(",").map(&:strip).reject(&:empty?).uniq.sort
          return base.strip if extras.empty?

          "#{base.strip}[#{extras.join(",")}]"
        end
        private :normalize_name

        sig { override.params(name: String, with: T.nilable(T::Array[String])).returns(Object) }
        def package_record(name, with: nil)
          normalized_options(name, with: with || [])
        end

        sig { params(name: String, with: T::Array[String]).returns(Tool) }
        def normalized_options(name, with:)
          {
            name: normalize_name(name),
            with: normalize_with(with),
          }
        end
        private :normalized_options

        sig { params(package: ToolEntry).returns(String) }
        def package_name(package)
          package[:name]
        end
        private :package_name

        sig { params(package: ToolEntry).returns(T.nilable(T::Array[String])) }
        def package_with(package)
          if package.key?(:with)
            package[:with]
          else
            package[:options].fetch(:with, [])
          end
        end
        private :package_with

        sig { override.params(name: String, executable: Pathname).void }
        def uninstall_package!(name, executable: Pathname.new(""))
          Bundle.system(executable.to_s, "tool", "uninstall", name, verbose: false)
        end
      end

      sig { override.params(entries: T::Array[Object]).returns(T::Array[Object]) }
      def format_checkable(entries)
        checkable_entries(entries).map do |entry|
          entry = T.cast(entry, Dsl::Entry)
          with = if entry.options.is_a?(Hash)
            value = entry.options[:with]
            value.is_a?(Array) ? value : []
          else
            []
          end

          self.class.package_record(entry.name, with:)
        end
      end
    end
  end
end
