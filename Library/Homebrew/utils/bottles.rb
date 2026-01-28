# typed: strict
# frozen_string_literal: true

require "tab"

module Utils
  # Helper functions for bottles.
  #
  # @api internal
  module Bottles
    class << self
      # Gets the tag for the running OS.
      #
      # @api internal
      sig { params(tag: T.nilable(T.any(Symbol, Tag))).returns(Tag) }
      def tag(tag = nil)
        case tag
        when Symbol
          Tag.from_symbol(tag)
        when Tag
          tag
        else
          @tag ||= T.let(Tag.new(
                           system: HOMEBREW_SYSTEM.downcase.to_sym,
                           arch:   HOMEBREW_PROCESSOR.downcase.to_sym,
                         ), T.nilable(Tag))
        end
      end

      sig { params(formula: Formula).returns(T::Boolean) }
      def built_as?(formula)
        return false unless formula.latest_version_installed?

        tab = Keg.new(formula.latest_installed_prefix).tab
        tab.built_as_bottle
      end

      sig { params(formula: Formula, file: Pathname).returns(T::Boolean) }
      def file_outdated?(formula, file)
        file = file.resolved_path

        filename = file.basename.to_s
        bottle = formula.bottle
        return false unless bottle

        _, bottle_tag, bottle_rebuild = extname_tag_rebuild(filename)
        return false if bottle_tag.blank?

        bottle_tag != bottle.tag.to_s || bottle_rebuild.to_i != bottle.rebuild
      end

      sig { params(filename: String).returns(T::Array[String]) }
      def extname_tag_rebuild(filename)
        HOMEBREW_BOTTLES_EXTNAME_REGEX.match(filename).to_a
      end

      sig { params(bottle_file: Pathname).returns(T.nilable(String)) }
      def receipt_path(bottle_file)
        bottle_file_list(bottle_file).find do |line|
          %r{.+/.+/INSTALL_RECEIPT.json}.match?(line)
        end
      end

      sig { params(bottle_file: Pathname, file_path: String).returns(String) }
      def file_from_bottle(bottle_file, file_path)
        Utils.popen_read("tar", "--extract", "--to-stdout", "--file", bottle_file, file_path)
      end

      sig { params(bottle_file: Pathname).returns([String, String]) }
      def resolve_formula_names(bottle_file)
        name = bottle_file_list(bottle_file).first.to_s.split("/").fetch(0)
        full_name = if (receipt_file_path = receipt_path(bottle_file))
          receipt_file = file_from_bottle(bottle_file, receipt_file_path)
          tap = Tab.from_file_content(receipt_file, "#{bottle_file}/#{receipt_file_path}").tap
          "#{tap}/#{name}" if tap.present? && !tap.core_tap?
        else
          bottle_json_path = Pathname(bottle_file.sub(/\.(\d+\.)?tar\.gz$/, ".json"))
          if bottle_json_path.exist? &&
             (bottle_json_path_contents = bottle_json_path.read.presence) &&
             (bottle_json = JSON.parse(bottle_json_path_contents).presence) &&
             bottle_json.is_a?(Hash)
            bottle_json.keys.first.presence
          end
        end
        full_name ||= name

        [name, full_name]
      end

      sig { params(bottle_file: Pathname).returns(PkgVersion) }
      def resolve_version(bottle_file)
        version = bottle_file_list(bottle_file).first.to_s.split("/").fetch(1)
        PkgVersion.parse(version)
      end

      sig { params(bottle_file: Pathname, name: String).returns(String) }
      def formula_contents(bottle_file, name: resolve_formula_names(bottle_file)[0])
        bottle_version = resolve_version bottle_file
        formula_path = "#{name}/#{bottle_version}/.brew/#{name}.rb"
        contents = file_from_bottle(bottle_file, formula_path)
        raise BottleFormulaUnavailableError.new(bottle_file, formula_path) unless $CHILD_STATUS.success?

        contents
      end

      sig {
        params(root_url: String, name: String, checksum: T.any(Checksum, String),
               filename: T.nilable(Bottle::Filename)).returns(T.any([String, T.nilable(String)], String))
      }
      def path_resolved_basename(root_url, name, checksum, filename)
        if root_url.match?(GitHubPackages::URL_REGEX)
          image_name = GitHubPackages.image_formula_name(name)
          ["#{image_name}/blobs/sha256:#{checksum}", filename&.github_packages]
        else
          filename&.url_encode
        end
      end

      sig { params(formula: Formula).returns(Tab) }
      def load_tab(formula)
        keg = Keg.new(formula.prefix)
        tabfile = keg/AbstractTab::FILENAME
        bottle_json_path = formula.local_bottle_path&.sub(/\.(\d+\.)?tar\.gz$/, ".json")

        if (tab_attributes = formula.bottle_tab_attributes.presence)
          tab = Tab.from_file_content(tab_attributes.to_json, tabfile)
          return tab if tab.built_on["os"] == HOMEBREW_SYSTEM
        elsif !tabfile.exist? && bottle_json_path&.exist?
          _, tag, = Utils::Bottles.extname_tag_rebuild(formula.local_bottle_path.to_s)
          bottle_hash = JSON.parse(File.read(bottle_json_path))
          tab_json = bottle_hash[formula.full_name]["bottle"]["tags"][tag]["tab"].to_json
          return Tab.from_file_content(tab_json, tabfile)
        else
          tab = keg.tab
        end

        tab.runtime_dependencies = begin
          f_runtime_deps = formula.runtime_dependencies(read_from_tab: false)
          Tab.runtime_deps_hash(formula, f_runtime_deps)
        end

        tab
      end

      private

      sig { params(bottle_file: Pathname).returns(T::Array[String]) }
      def bottle_file_list(bottle_file)
        @bottle_file_list ||= T.let({}, T.nilable(T::Hash[Pathname, T::Array[String]]))
        @bottle_file_list[bottle_file] ||= Utils.popen_read("tar", "--list", "--file", bottle_file)
                                                .lines
                                                .map(&:chomp)
      end
    end

    # Denotes the arch and OS of a bottle.
    class Tag
      sig { returns(Symbol) }
      attr_reader :system, :arch

      sig { params(value: Symbol).returns(T.attached_class) }
      def self.from_symbol(value)
        return new(system: :all, arch: :all) if value == :all

        @all_archs_regex ||= T.let(begin
          all_archs = Hardware::CPU::ALL_ARCHS.map(&:to_s)
          /
            ^((?<arch>#{Regexp.union(all_archs)})_)?
            (?<system>[\w.]+)$
          /x
        end, T.nilable(Regexp))
        match = @all_archs_regex.match(value.to_s)
        raise ArgumentError, "Invalid bottle tag symbol" unless match

        system = T.must(match[:system]).to_sym
        arch = match[:arch]&.to_sym || :x86_64
        new(system:, arch:)
      end

      sig { params(system: Symbol, arch: Symbol).void }
      def initialize(system:, arch:)
        @system = system
        @arch = arch
      end

      sig { override.params(other: BasicObject).returns(T::Boolean) }
      def ==(other)
        case other
        when Symbol
          to_sym == other
        when self.class
          system == other.system && standardized_arch == other.standardized_arch
        else false
        end
      end

      sig { override.params(other: BasicObject).returns(T::Boolean) }
      def eql?(other)
        case other
        when self.class
          self == other
        else false
        end
      end

      sig { override.returns(Integer) }
      def hash
        [system, standardized_arch].hash
      end

      sig { returns(Symbol) }
      def standardized_arch
        return :x86_64 if [:x86_64, :intel].include? arch
        return :arm64 if [:arm64, :arm, :aarch64].include? arch

        arch
      end

      sig { returns(Symbol) }
      def to_sym
        arch_to_symbol(standardized_arch)
      end

      sig { override.returns(String) }
      def to_s
        to_sym.to_s
      end

      sig { returns(Symbol) }
      def to_unstandardized_sym
        # Never allow these generic names
        return to_sym if [:intel, :arm].include? arch

        # Backwards compatibility with older bottle names
        arch_to_symbol(arch)
      end

      sig { returns(MacOSVersion) }
      def to_macos_version
        @to_macos_version ||= T.let(MacOSVersion.from_symbol(system), T.nilable(MacOSVersion))
      end

      sig { returns(T::Boolean) }
      def linux?
        system == :linux
      end

      sig { returns(T::Boolean) }
      def macos?
        MacOSVersion::SYMBOLS.key?(system)
      end

      sig { returns(T::Boolean) }
      def valid_combination?
        return true unless [:arm64, :arm, :aarch64].include? arch
        return true unless macos?

        # Big Sur is the first version of macOS that runs on ARM
        to_macos_version >= :big_sur
      end

      sig { returns(String) }
      def default_prefix
        if linux?
          HOMEBREW_LINUX_DEFAULT_PREFIX
        elsif standardized_arch == :arm64
          HOMEBREW_MACOS_ARM_DEFAULT_PREFIX
        else
          HOMEBREW_DEFAULT_PREFIX
        end
      end

      sig { returns(String) }
      def default_cellar
        if linux?
          Homebrew::DEFAULT_LINUX_CELLAR
        elsif standardized_arch == :arm64
          Homebrew::DEFAULT_MACOS_ARM_CELLAR
        else
          Homebrew::DEFAULT_MACOS_CELLAR
        end
      end

      private

      sig { params(arch: Symbol).returns(Symbol) }
      def arch_to_symbol(arch)
        if system == :all && arch == :all
          :all
        elsif macos? && standardized_arch == :x86_64
          system
        else
          :"#{arch}_#{system}"
        end
      end
    end

    # The specification for a specific tag
    class TagSpecification
      sig { returns(Utils::Bottles::Tag) }
      attr_reader :tag

      sig { returns(Checksum) }
      attr_reader :checksum

      sig { returns(T.any(Symbol, String)) }
      attr_reader :cellar

      sig { params(tag: Utils::Bottles::Tag, checksum: Checksum, cellar: T.any(Symbol, String)).void }
      def initialize(tag:, checksum:, cellar:)
        @tag = tag
        @checksum = checksum
        @cellar = cellar
      end

      sig { override.params(other: BasicObject).returns(T::Boolean) }
      def ==(other)
        case other
        when self.class
          tag == other.tag && checksum == other.checksum && cellar == other.cellar
        else false
        end
      end
      alias eql? ==
    end

    # Collector for bottle specifications.
    class Collector
      sig { void }
      def initialize
        @tag_specs = T.let({}, T::Hash[Utils::Bottles::Tag, Utils::Bottles::TagSpecification])
      end

      sig { returns(T::Array[Utils::Bottles::Tag]) }
      def tags
        @tag_specs.keys
      end

      sig { override.params(other: BasicObject).returns(T::Boolean) }
      def ==(other)
        case other
        when self.class
          @tag_specs == other.tag_specs
        else false
        end
      end
      alias eql? ==

      sig { params(tag: Utils::Bottles::Tag, checksum: Checksum, cellar: T.any(Symbol, String)).void }
      def add(tag, checksum:, cellar:)
        spec = Utils::Bottles::TagSpecification.new(tag:, checksum:, cellar:)
        @tag_specs[tag] = spec
      end

      sig { params(tag: Utils::Bottles::Tag, no_older_versions: T::Boolean).returns(T::Boolean) }
      def tag?(tag, no_older_versions: false)
        tag = find_matching_tag(tag, no_older_versions:)
        tag.present?
      end

      sig { params(block: T.proc.params(tag: Utils::Bottles::Tag).void).void }
      def each_tag(&block)
        @tag_specs.each_key(&block)
      end

      sig {
        params(tag: Utils::Bottles::Tag, no_older_versions: T::Boolean)
          .returns(T.nilable(Utils::Bottles::TagSpecification))
      }
      def specification_for(tag, no_older_versions: false)
        tag = find_matching_tag(tag, no_older_versions:)
        @tag_specs[tag] if tag
      end

      protected

      sig { returns(T::Hash[Utils::Bottles::Tag, Utils::Bottles::TagSpecification]) }
      attr_reader :tag_specs

      private

      sig { params(tag: Utils::Bottles::Tag, no_older_versions: T::Boolean).returns(T.nilable(Utils::Bottles::Tag)) }
      def find_matching_tag(tag, no_older_versions: false)
        if @tag_specs.key?(tag)
          tag
        else
          all = Tag.from_symbol(:all)
          all if @tag_specs.key?(all)
        end
      end
    end
  end
end

require "extend/os/bottles"
