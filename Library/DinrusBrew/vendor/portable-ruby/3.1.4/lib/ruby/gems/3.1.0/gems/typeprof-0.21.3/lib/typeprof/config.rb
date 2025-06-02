require "rbconfig"

module TypeProf
  ConfigData = Struct.new(
    :rb_files,
    :rbs_files,
    :output,
    :gem_rbs_features,
    :collection_path,
    :verbose,
    :dir_filter,
    :max_iter,
    :max_sec,
    :options,
    :lsp_options,
    :lsp,
    keyword_init: true
  )

  class TypeProfError < StandardError
    def report(output)
      output.puts "# Analysis Error"
      output.puts message
    end
  end

  class ConfigData
    def initialize(**opt)
      opt[:output] ||= $stdout
      opt[:gem_rbs_features] ||= []
      opt[:dir_filter] ||= DEFAULT_DIR_FILTER
      opt[:verbose] ||= 0
      opt[:options] ||= {}
      opt[:options] = {
        exclude_untyped: false,
        show_typeprof_version: true,
        show_indicator: true,
        show_untyped: false,
        show_errors: false,
        show_parameter_names: true,
        show_source_locations: false,
        stub_execution: true,
        type_depth_limit: 5,
        union_width_limit: 10,
        stackprof: nil,
      }.merge(opt[:options])
      opt[:lsp_options] = {
        port: 0,
        stdio: false,
      }.merge(opt[:lsp_options] || {})
      super(**opt)
    end

    def check_dir_filter(path)
      dir_filter.reverse_each do |cond, dir|
        return cond unless dir
        return cond if path.start_with?(dir)
      end
    end

    DEFAULT_DIR_FILTER = [
      [:include],
      [:exclude, RbConfig::CONFIG["prefix"]],
      [:exclude, Gem.dir],
      [:exclude, Gem.user_dir],
    ]
  end

  module Config
    def self.current
      Thread.current[:typeprof_config]
    end

    def self.set_current(config)
      Thread.current[:typeprof_config] = config
    end
  end

  def self.analyze(config, cancel_token = nil)
    # Deploy the config to the TypeProf::Config (Note: This is thread local)
    Config.set_current(config)

    if Config.current.options[:stackprof]
      require "stackprof"
      out = "typeprof-stackprof-#{ Config.current.options[:stackprof] }.dump"
      StackProf.start(mode: Config.current.options[:stackprof], out: out, raw: true)
    end

    scratch = Scratch.new
    Builtin.setup_initial_global_env(scratch)

    Config.current.gem_rbs_features.each do |feature|
      Import.import_library(scratch, feature)
    end

    rbs_files = []
    rbs_codes = []
    Config.current.rbs_files.each do |rbs|
      if rbs.is_a?(Array) # [String name, String content]
        rbs_codes << rbs
      else
        rbs_files << rbs
      end
    end
    Import.import_rbs_files(scratch, rbs_files)
    rbs_codes.each do |name, content|
      Import.import_rbs_code(scratch, name, content)
    end

    def_code_range_table = nil
    caller_code_range_table = nil
    Config.current.rb_files.each do |rb|
      if rb.is_a?(Array) # [String name, String content]
        iseq, def_tbl, caller_tbl = ISeq.compile_str(*rb.reverse)
        def_code_range_table ||= def_tbl
        caller_code_range_table ||= caller_tbl
      else
        iseq = rb
      end
      scratch.add_entrypoint(iseq)
    end

    result = scratch.type_profile(cancel_token)

    if Config.current.options[:lsp]
      return scratch.report_lsp, def_code_range_table, caller_code_range_table
    end

    if Config.current.output.respond_to?(:write)
      scratch.report(result, Config.current.output)
    else
      open(Config.current.output, "w") do |output|
        scratch.report(result, output)
      end
    end

  rescue TypeProfError => exc
    exc.report(Config.current.output)

    return nil
  ensure
    if Config.current.options[:stackprof] && defined?(StackProf)
      StackProf.stop
      StackProf.results
    end
  end

  def self.starting_state(iseq)
    cref = CRef.new(:bottom, Type::Builtin[:obj], false) # object
    recv = Type::Instance.new(Type::Builtin[:obj])
    ctx = Context.new(iseq, cref, nil)
    ep = ExecutionPoint.new(ctx, 0, nil)
    locals = [Type.nil] * iseq.locals.size
    env = Env.new(StaticEnv.new(recv, Type.nil, false, false), locals, [], Utils::HashWrapper.new({}))

    return ep, env
  end
end
