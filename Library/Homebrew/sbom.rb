# typed: true
# frozen_string_literal: true

require "cxxstdlib"
require "options"
require "json"
require "development_tools"
require "extend/cachable"

# Rather than calling `new` directly, use one of the class methods like {SBOM.create}.
class SBOM
  extend Cachable

  FILENAME = "sbom.spdx.json"

  attr_accessor :homebrew_version, :spdxfile, :built_as_bottle, :installed_as_dependency, :installed_on_request,
                :changed_files, :poured_from_bottle, :loaded_from_api, :time, :stdlib, :aliases, :arch, :source,
                :built_on, :license, :name
  attr_writer :compiler, :runtime_dependencies, :source_modified_time

  # Instantiates a {SBOM} for a new installation of a formula.
  sig { params(formula: Formula, compiler: T.nilable(String), stdlib: T.nilable(String)).returns(T.attached_class) }
  def self.create(formula, compiler = nil, stdlib = nil)
    build = formula.build
    runtime_deps = formula.runtime_dependencies(undeclared: false)
    attributes = {
      "name"                    => formula.name,
      "homebrew_version"        => HOMEBREW_VERSION,
      "spdxfile"                => formula.prefix/FILENAME,
      "built_as_bottle"         => build.bottle?,
      "installed_as_dependency" => false,
      "installed_on_request"    => false,
      "poured_from_bottle"      => false,
      "loaded_from_api"         => false,
      "time"                    => Time.now.to_i,
      "source_modified_time"    => formula.source_modified_time.to_i,
      "compiler"                => compiler,
      "stdlib"                  => stdlib,
      "aliases"                 => formula.aliases,
      "runtime_dependencies"    => SBOM.runtime_deps_hash(formula, runtime_deps),
      "arch"                    => Hardware::CPU.arch,
      "license"                 => SPDX.license_expression_to_string(formula.license),
      "built_on"                => DevelopmentTools.build_system_info,
      "source"                  => {
        "path"         => formula.specified_path.to_s,
        "tap"          => formula.tap&.name,
        "tap_git_head" => nil, # Filled in later if possible
        "spec"         => formula.active_spec_sym.to_s,
        "patches"      => formula.stable&.patches,
        "bottle"       => formula.bottle_hash,
        "stable"       => {
          "version"  => formula.stable&.version,
          "url"      => formula.stable&.url,
          "checksum" => formula.stable&.checksum,
        },
      },
    }

    # We can only get `tap_git_head` if the tap is installed locally
    attributes["source"]["tap_git_head"] = T.must(formula.tap).git_head if formula.tap&.installed?

    new(attributes)
  end

  sig { params(attributes: Hash).void }
  def initialize(attributes = {})
    attributes.each { |key, value| instance_variable_set(:"@#{key}", value) }
  end

  sig { params(formula: Formula, deps: T::Array[Dependency]).returns(T::Array[Hash]) }
  def self.runtime_deps_hash(formula, deps)
    deps.map do |dep|
      f = dep.to_formula
      {
        "full_name"         => f.full_name,
        "name"              => f.name,
        "version"           => f.version.to_s,
        "revision"          => f.revision,
        "pkg_version"       => f.pkg_version.to_s,
        "declared_directly" => formula.deps.include?(dep),
        "license"           => SPDX.license_expression_to_string(f.license),
        "bottle"            => f.bottle_hash,
      }
    end
  end

  sig { returns(T::Boolean) }
  def stable?
    spec == :stable
  end

  sig { returns(Symbol) }
  def compiler
    @compiler || DevelopmentTools.default_compiler
  end

  sig { returns(CxxStdlib) }
  def cxxstdlib
    # Older sboms won't have these values, so provide sensible defaults
    lib = stdlib.to_sym if stdlib
    CxxStdlib.create(lib, compiler.to_sym)
  end

  sig { returns(T::Boolean) }
  def built_bottle?
    built_as_bottle && !poured_from_bottle
  end

  sig { returns(T::Boolean) }
  def bottle?
    built_as_bottle
  end

  sig { returns(T.nilable(Tap)) }
  def tap
    tap_name = source["tap"]
    Tap.fetch(tap_name) if tap_name
  end

  sig { returns(Symbol) }
  def spec
    source["spec"].to_sym
  end

  sig { returns(T.nilable(Version)) }
  def stable_version
    source["stable"]["version"]
  end

  sig { returns(Time) }
  def source_modified_time
    Time.at(@source_modified_time || 0)
  end

  sig { void }
  def write
    # If this is a new installation, the cache of installed formulae
    # will no longer be valid.
    Formula.clear_cache unless spdxfile.exist?

    self.class.cache[spdxfile] = self
    spdxfile.atomic_write(JSON.pretty_generate(to_spdx_sbom))
  end

  sig { params(runtime_dependency_declaration: T::Array[Hash], compiler_declaration: Hash).returns(T::Array[Hash]) }
  def generate_relations_json(runtime_dependency_declaration, compiler_declaration)
    runtime = runtime_dependency_declaration.map do |dependency|
      {
        "spdxElementId"      => dependency["SPDXID"],
        "relationshipType"   => "RUNTIME_DEPENDENCY_OF",
        "relatedSpdxElement" => "SPDXRef-Bottle-#{name}",
      }
    end
    patches = source["patches"].map do |_patch|
      {
        "spdxElementId"      => "SPDXRef-Patch-#{name}",
        "relationshipType"   => "PATCH_APPLIED",
        "relatedSpdxElement" => "SPDXRef-Archive-#{name}-src",
      }
    end

    base = [
      {
        "spdxElementId"      => "SPDXRef-File-#{name}",
        "relationshipType"   => "PACKAGE_OF",
        "relatedSpdxElement" => "SPDXRef-Archive-#{name}-src",
      },
      {
        "spdxElementId"      => "SPDXRef-Compiler",
        "relationshipType"   => "BUILD_TOOL_OF",
        "relatedSpdxElement" => "SPDXRef-Package-#{name}-src",
      },
    ]

    if compiler_declaration["SPDXRef-Stdlib"].present?
      base += {
        "spdxElementId"      => "SPDXRef-Stdlib",
        "relationshipType"   => "DEPENDENCY_OF",
        "relatedSpdxElement" => "SPDXRef-Bottle-#{name}",
      }
    end

    runtime + patches + base
  end

  sig { params(runtime_dependency_declaration: T::Array[Hash], compiler_declaration: Hash).returns(T::Array[Hash]) }
  def generate_packages_json(runtime_dependency_declaration, compiler_declaration)
    bottle = []
    if get_bottle_info(source["bottle"])
      bottle += {
        "SPDXID"           => "SPDXRef-Bottle-#{name}",
        "name"             => name.to_s,
        "versionInfo"      => stable_version.to_s,
        "filesAnalyzed"    => false,
        "licenseDeclared"  => "NOASSERTION",
        "builtDate"        => source_modified_time,
        "licenseConcluded" => license,
        "downloadLocation" => T.must(get_bottle_info(source["bottle"]))["url"],
        "copyrightText"    => "NOASSERTION",
        "externalRefs"     => [
          {
            "referenceCategory" => "PACKAGE-MANAGER",
            "referenceLocator"  => "pkg:brew/#{tap}/#{name}@#{stable_version}",
            "referenceType"     => "purl",
          },
        ],
        "checksums"        => [
          {
            "algorithm"     => "SHA256",
            "checksumValue" => T.must(get_bottle_info(source["bottle"]))["sha256"],
          },
        ],
      }
    end

    [
      {
        "SPDXID"           => "SPDXRef-Archive-#{name}-src",
        "name"             => name.to_s,
        "versionInfo"      => stable_version.to_s,
        "filesAnalyzed"    => false,
        "licenseDeclared"  => "NOASSERTION",
        "builtDate"        => source_modified_time,
        "licenseConcluded" => license || "NOASSERTION",
        "downloadLocation" => source["stable"]["url"],
        "copyrightText"    => "NOASSERTION",
        "externalRefs"     => [],
        "checksums"        => [
          {
            "algorithm"     => "SHA256",
            "checksumValue" => source["stable"]["checksum"],
          },
        ],
      },
    ] + runtime_dependency_declaration + compiler_declaration.values + bottle
  end

  sig { returns(Hash) }
  def to_spdx_sbom
    runtime_full = []

    if @runtime_dependencies.present?
      runtime_full = @runtime_dependencies.map do |dependency|
        bottle_info = get_bottle_info(dependency["bottle"])
        {
          "SPDXID"           => "SPDXRef-Package-SPDXRef-#{dependency["name"].tr("/", "-")}-#{dependency["version"]}",
          "name"             => dependency["name"],
          "versionInfo"      => dependency["pkg_version"],
          "filesAnalyzed"    => false,
          "licenseDeclared"  => "NOASSERTION",
          "licenseConcluded" => dependency["license"] || "NOASSERTION",
          "downloadLocation" => bottle_info.present? ? bottle_info["url"] : "NOASSERTION",
          "copyrightText"    => "NOASSERTION",
          "checksums"        => [
            {
              "algorithm"     => "SHA256",
              "checksumValue" => bottle_info.present? ? bottle_info["sha256"] : "NOASSERTION",
            },
          ],
          "externalRefs"     => [
            {
              "referenceCategory" => "PACKAGE-MANAGER",
              "referenceLocator"  => "pkg:brew/#{dependency["full_name"]}@#{dependency["version"]}",
              "referenceType"     => "purl",
            },
          ],
        }
      end
    end

    compiler_info = {
      "SPDXRef-Compiler" => {
        "SPDXID"           => "SPDXRef-Compiler",
        "name"             => compiler,
        "versionInfo"      => built_on["xcode"],
        "filesAnalyzed"    => false,
        "licenseDeclared"  => "NOASSERTION",
        "licenseConcluded" => "NOASSERTION",
        "copyrightText"    => "NOASSERTION",
        "downloadLocation" => "NOASSERTION",
        "checksums"        => [],
        "externalRefs"     => [],
      },
    }

    if stdlib.present?
      compiler_info["SPDXRef-Stdlib"] = {
        "SPDXID"           => "SPDXRef-Stdlib",
        "name"             => stdlib,
        "versionInfo"      => stdlib,
        "filesAnalyzed"    => false,
        "licenseDeclared"  => "NOASSERTION",
        "licenseConcluded" => "NOASSERTION",
        "copyrightText"    => "NOASSERTION",
        "downloadLocation" => "NOASSERTION",
        "checksums"        => [],
        "externalRefs"     => [],
      }
    end

    packages = generate_packages_json(runtime_full, compiler_info)
    {
      "SPDXID"            => "SPDXRef-DOCUMENT",
      "spdxVersion"       => "SPDX-2.3",
      "name"              => "SBOM-SPDX-#{name}-#{stable_version}",
      "creationInfo"      => {
        "created"  => DateTime.now.to_s,
        "creators" => ["Tool: https://github.com/homebrew/brew@#{homebrew_version}"],
      },
      "dataLicense"       => "CC0-1.0",
      "documentNamespace" => "https://formulae.brew.sh/spdx/#{name}-#{stable_version}.json",
      "documentDescribes" => packages.map { |dependency| dependency["SPDXID"] },
      "files"             => [],
      "packages"          => packages,
      "relationships"     => generate_relations_json(runtime_full, compiler_info),
    }
  end

  sig { params(base: T::Hash[String, Hash]).returns(T.nilable(Hash)) }
  def get_bottle_info(base)
    return unless base.key?("files")

    T.must(base["files"])[Utils::Bottles.tag.to_sym]
  end
end
