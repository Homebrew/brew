# typed: strict

module Homebrew
  sig { returns(String) }
  def self.bootsnap_key; end
end

module Bootsnap
  sig {
    params(
      cache_dir:          String,
      development_mode:   T::Boolean,
      load_path_cache:    T::Boolean,
      ignore_directories: T.nilable(T::Array[String]),
      readonly:           T::Boolean,
      revalidation:       T::Boolean,
      compile_cache_iseq: T::Boolean,
      compile_cache_yaml: T::Boolean,
      compile_cache_json: T::Boolean,
    ).void
  }
  def self.setup(
    cache_dir:,
    development_mode: true,
    load_path_cache: true,
    ignore_directories: nil,
    readonly: false,
    revalidation: false,
    compile_cache_iseq: true,
    compile_cache_yaml: true,
    compile_cache_json: true
  ); end
end
