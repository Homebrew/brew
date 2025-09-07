# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

class BottleSpecification
  RELOCATABLE_CELLARS = [:any, :any_skip_relocation].freeze

  sig { returns(T.nilable(Tap)) }
  attr_accessor :tap

  attr_reader :collector

  sig { returns(T::Hash[Symbol, T.untyped]) }
  attr_reader :root_url_specs

  sig { returns(String) }
  attr_reader :repository

  sig { void }
  def initialize
    @rebuild = T.let(0, Integer)
    @repository = T.let(Homebrew::DEFAULT_REPOSITORY, String)
    @collector = T.let(Utils::Bottles::Collector.new, Utils::Bottles::Collector)
    @root_url_specs = T.let({}, T::Hash[Symbol, T.untyped])
    @root_url = T.let(nil, T.nilable(String))
  end

  sig { params(val: Integer).returns(Integer) }
  def rebuild(val = T.unsafe(nil))
    val.nil? ? @rebuild : @rebuild = val
  end

  def root_url(var = nil, specs = {})
    if var.nil?
      @root_url ||= if (github_packages_url = GitHubPackages.root_url_if_match(Homebrew::EnvConfig.bottle_domain))
        github_packages_url
      else
        Homebrew::EnvConfig.bottle_domain
      end
    else
      @root_url = if (github_packages_url = GitHubPackages.root_url_if_match(var))
        github_packages_url
      else
        var
      end
      @root_url_specs.merge!(specs)
    end
  end

  def ==(other)
    self.class == other.class && rebuild == other.rebuild && collector == other.collector &&
      root_url == other.root_url && root_url_specs == other.root_url_specs && tap == other.tap
  end
  alias eql? ==

  sig { params(tag: Utils::Bottles::Tag).returns(T.any(Symbol, String)) }
  def tag_to_cellar(tag = Utils::Bottles.tag)
    spec = collector.specification_for(tag)
    if spec.present?
      spec.cellar
    else
      tag.default_cellar
    end
  end

  sig { params(tag: Utils::Bottles::Tag).returns(T::Boolean) }
  def compatible_locations?(tag: Utils::Bottles.tag)
    cellar = tag_to_cellar(tag)

    return true if RELOCATABLE_CELLARS.include?(cellar)

    prefix = Pathname(cellar.to_s).parent.to_s

    cellar_relocatable = cellar.size >= HOMEBREW_CELLAR.to_s.size && ENV["HOMEBREW_RELOCATE_BUILD_PREFIX"].present?
    prefix_relocatable = prefix.size >= HOMEBREW_PREFIX.to_s.size && ENV["HOMEBREW_RELOCATE_BUILD_PREFIX"].present?

    compatible_cellar = cellar == HOMEBREW_CELLAR.to_s || cellar_relocatable
    compatible_prefix = prefix == HOMEBREW_PREFIX.to_s || prefix_relocatable

    compatible_cellar && compatible_prefix
  end

  # Does the {Bottle} this {BottleSpecification} belongs to need to be relocated?
  sig { params(tag: Utils::Bottles::Tag).returns(T::Boolean) }
  def skip_relocation?(tag: Utils::Bottles.tag)
    spec = collector.specification_for(tag)
    spec&.cellar == :any_skip_relocation
  end

  sig { params(tag: T.any(Symbol, Utils::Bottles::Tag), no_older_versions: T::Boolean).returns(T::Boolean) }
  def tag?(tag, no_older_versions: false)
    collector.tag?(tag, no_older_versions:)
  end

  # Checksum methods in the DSL's bottle block take
  # a Hash, which indicates the platform the checksum applies on.
  # Example bottle block syntax:
  # bottle do
  #  sha256 cellar: :any_skip_relocation, big_sur: "69489ae397e4645..."
  #  sha256 cellar: :any, catalina: "449de5ea35d0e94..."
  # end
  def sha256(hash)
    sha256_regex = /^[a-f0-9]{64}$/i

    # find new `sha256 big_sur: "69489ae397e4645..."` format
    tag, digest = hash.find do |key, value|
      key.is_a?(Symbol) && value.is_a?(String) && value.match?(sha256_regex)
    end

    cellar = hash[:cellar] if digest && tag

    tag = Utils::Bottles::Tag.from_symbol(tag)

    cellar ||= tag.default_cellar

    collector.add(tag, checksum: Checksum.new(digest), cellar:)
  end

  sig {
    params(tag: Utils::Bottles::Tag, no_older_versions: T::Boolean)
      .returns(T.nilable(Utils::Bottles::TagSpecification))
  }
  def tag_specification_for(tag, no_older_versions: false)
    collector.specification_for(tag, no_older_versions:)
  end

  def checksums
    tags = collector.tags.sort_by do |tag|
      version = tag.to_macos_version
      # Give `arm64` bottles a higher priority so they are first.
      priority = (tag.arch == :arm64) ? 3 : 2
      "#{priority}.#{version}_#{tag}"
    rescue MacOSVersion::Error
      # Sort non-macOS tags below macOS tags, and arm64 tags before other tags.
      priority = (tag.arch == :arm64) ? 1 : 0
      "#{priority}.#{tag}"
    end
    tags.reverse.map do |tag|
      spec = collector.specification_for(tag)
      {
        "tag"    => spec.tag.to_sym,
        "digest" => spec.checksum,
        "cellar" => spec.cellar,
      }
    end
  end
end

require "extend/os/bottle_specification"
