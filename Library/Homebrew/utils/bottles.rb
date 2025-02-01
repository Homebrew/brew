# typed: true # rubocop:todo Sorbet/StrictSigil
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
          @tag ||= Tag.new(
            system: HOMEBREW_SYSTEM.downcase.to_sym,
            arch:   HOMEBREW_PROCESSOR.downcase.to_sym,
          )
        end
      end

      def built_as?(formula)
        return false unless formula.latest_version_installed?

        tab = Keg.new(formula.latest_installed_prefix).tab
        tab.built_as_bottle
      end

      def file_outdated?(formula, file)
        file = file.resolved_path

        filename = file.basename.to_s
        return false if formula.bottle.blank?

        _, bottle_tag, bottle_rebuild = extname_tag_rebuild(filename)
        return false if bottle_tag.blank?

        bottle_tag != formula.bottle.tag.to_s || bottle_rebuild.to_i != formula.bottle.rebuild
      end

      def extname_tag_rebuild(filename)
        HOMEBREW_BOTTLES_EXTNAME_REGEX.match(filename).to_a
      end

      def receipt_path(bottle_file)
        bottle_file_list(bottle_file).find do |line|
          %r{.+/.+/INSTALL_RECEIPT.json}.match?(line)
        end
      end

      def file_from_bottle(bottle_file, file_path)
        Utils.popen_read("tar", "--extract", "--to-stdout", "--file", bottle_file, file_path)
      end

      def resolve_formula_names(bottle_file)
        name = bottle_file_list(bottle_file).first.to_s.split("/").first
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

      def resolve_version(bottle_file)
        version = bottle_file_list(bottle_file).first.to_s.split("/").second
        PkgVersion.parse(version)
      end

      def formula_contents(bottle_file,
                           name: resolve_formula_names(bottle_file)[0])
        bottle_version = resolve_version bottle_file
        formula_path = "#{name}/#{bottle_version}/.brew/#{name}.rb"
        contents = file_from_bottle(bottle_file, formula_path)
        raise BottleFormulaUnavailableError.new(bottle_file, formula_path) unless $CHILD_STATUS.success?

        contents
      end

      def path_resolved_basename(root_url, name, checksum, filename)
        if root_url.match?(GitHubPackages::URL_REGEX)
          image_name = GitHubPackages.image_formula_name(name)
          ["#{image_name}/blobs/sha256:#{checksum}", filename&.github_packages]
        else
          filename&.url_encode
        end
      end

      def load_tab(formula)
        keg = Keg.new(formula.prefix)
        tabfile = keg/AbstractTab::FILENAME
        bottle_json_path = formula.local_bottle_path&.sub(/\.(\d+\.)?tar\.gz$/, ".json")

        if (tab_attributes = formula.bottle_tab_attributes.presence)
          Tab.from_file_content(tab_attributes.to_json, tabfile)
        elsif !tabfile.exist? && bottle_json_path&.exist?
          _, tag, = Utils::Bottles.extname_tag_rebuild(formula.local_bottle_path)
          bottle_hash = JSON.parse(File.read(bottle_json_path))
          tab_json = bottle_hash[formula.full_name]["bottle"]["tags"][tag]["tab"].to_json
          Tab.from_file_content(tab_json, tabfile)
        else
          tab = keg.tab

          tab.runtime_dependencies = begin
            f_runtime_deps = formula.runtime_dependencies(read_from_tab: false)
            Tab.runtime_deps_hash(formula, f_runtime_deps)
          end

          tab
        end
      end

      private

      def bottle_file_list(bottle_file)
        @bottle_file_list ||= {}
        @bottle_file_list[bottle_file] ||= Utils.popen_read("tar", "--list", "--file", bottle_file)
                                                .lines
                                                .map(&:chomp)
      end
    end

    # Denotes the arch and OS of a bottle.
    class Tag
      attr_reader :system, :arch

      sig { params(value: Symbol).returns(T.attached_class) }
      def self.from_symbol(value)
        return new(system: :all, arch: :all) if value == :all

        @all_archs_regex ||= begin
          all_archs = Hardware::CPU::ALL_ARCHS.map(&:to_s)
          /
            ^((?<arch>#{Regexp.union(all_archs)})_)?
            (?<system>[\w.]+)$
          /x
        end
        match = @all_archs_regex.match(value.to_s)
        raise ArgumentError, "Invalid bottle tag symbol" unless match

        system = match[:system].to_sym
        arch = match[:arch]&.to_sym || :x86_64
        new(system:, arch:)
      end

      sig { params(system: Symbol, arch: Symbol).void }
      def initialize(system:, arch:)
        @system = system
        @arch = arch
      end

      def ==(other)
        if other.is_a?(Symbol)
          to_sym == other
        else
          self.class == other.class && system == other.system && standardized_arch == other.standardized_arch
        end
      end

      def eql?(other)
        self.class == other.class && self == other
      end

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

      sig { returns(String) }
      def to_s
        to_sym.to_s
      end

      def to_unstandardized_sym
        # Never allow these generic names
        return to_sym if [:intel, :arm].include? arch

        # Backwards compatibility with older bottle names
        arch_to_symbol(arch)
      end

      sig { returns(MacOSVersion) }
      def to_macos_version
        @to_macos_version ||= MacOSVersion.from_symbol(system)
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

      def initialize(tag:, checksum:, cellar:)
        @tag = tag
        @checksum = checksum
        @cellar = cellar
      end

      def ==(other)
        self.class == other.class && tag == other.tag && checksum == other.checksum && cellar == other.cellar
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

      def ==(other)
        self.class == other.class && @tag_specs == other.instance_variable_get(:@tag_specs)
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

      private

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
