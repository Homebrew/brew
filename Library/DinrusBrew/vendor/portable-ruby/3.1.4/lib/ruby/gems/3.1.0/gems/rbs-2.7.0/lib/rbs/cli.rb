# frozen_string_literal: true

require "open3"
require "optparse"
require "shellwords"

module RBS
  class CLI
    class LibraryOptions
      attr_accessor :core_root
      attr_accessor :config_path
      attr_reader :repos
      attr_reader :libs
      attr_reader :dirs

      def initialize()
        @core_root = EnvironmentLoader::DEFAULT_CORE_ROOT
        @repos = []

        @libs = []
        @dirs = []
        @config_path = Collection::Config::PATH
      end

      def loader
        repository = Repository.new(no_stdlib: core_root.nil?)
        repos.each do |repo|
          repository.add(Pathname(repo))
        end

        loader = EnvironmentLoader.new(core_root: core_root, repository: repository)
        lock = config_path&.then { |p| Collection::Config.lockfile_of(p) }
        loader.add_collection(lock) if lock

        dirs.each do |dir|
          loader.add(path: Pathname(dir))
        end

        libs.each do |lib|
          name, version = lib.split(/:/, 2)
          next unless name
          loader.add(library: name, version: version)
        end

        loader
      end

      def setup_library_options(opts)
        opts.on("-r LIBRARY", "Load RBS files of the library") do |lib|
          libs << lib
        end

        opts.on("-I DIR", "Load RBS files from the directory") do |dir|
          dirs << dir
        end

        opts.on("--no-stdlib", "Skip loading standard library signatures") do
          self.core_root = nil
        end

        opts.on('--collection PATH', "File path of collection configration (default: #{Collection::Config::PATH})") do |path|
          self.config_path = Pathname(path).expand_path
        end

        opts.on('--no-collection', 'Ignore collection configration') do
          self.config_path = nil
        end

        opts.on("--repo DIR", "Add RBS repository") do |dir|
          repos << dir
        end

        opts
      end
    end

    attr_reader :stdout
    attr_reader :stderr
    attr_reader :original_args

    def initialize(stdout:, stderr:)
      @stdout = stdout
      @stderr = stderr
    end

    COMMANDS = [:ast, :annotate, :list, :ancestors, :methods, :method, :validate, :constant, :paths, :prototype, :vendor, :parse, :test, :collection]

    def parse_logging_options(opts)
      opts.on("--log-level LEVEL", "Specify log level (defaults to `warn`)") do |level|
        RBS.logger_level = level
      end

      opts.on("--log-output OUTPUT", "Specify the file to output log (defaults to stderr)") do |output|
        io = File.open(output, "a") or raise
        RBS.logger_output = io
      end

      opts
    end

    def has_parser?
      defined?(RubyVM::AbstractSyntaxTree)
    end

    def run(args)
      @original_args = args.dup

      options = LibraryOptions.new

      opts = OptionParser.new
      opts.banner = <<~USAGE
        Usage: rbs [options...] [command...]

        Available commands: #{COMMANDS.join(", ")}, version, help.

        Options:
      USAGE
      options.setup_library_options(opts)
      parse_logging_options(opts)
      opts.version = RBS::VERSION

      opts.order!(args)

      command = args.shift&.to_sym

      case command
      when :version
        stdout.puts opts.ver
      when *COMMANDS
        __send__ :"run_#{command}", args, options
      else
        stdout.puts opts.help
      end
    end

    def run_ast(args, options)
      OptionParser.new do |opts|
        opts.banner = <<EOB
Usage: rbs ast [patterns...]

Print JSON AST of loaded environment.
You can specify patterns to filter declarations with the file names.

Examples:

  $ rbs ast
  $ rbs ast 'basic_object.rbs'
  $ rbs -I ./sig ast ./sig
  $ rbs -I ./sig ast '*/models/*.rbs'
EOB
      end.order!(args)

      patterns = args.map do |arg|
        path = Pathname(arg)
        if path.exist?
          # Pathname means a directory or a file
          path
        else
          # String means a `fnmatch` pattern
          arg
        end
      end

      loader = options.loader()

      env = Environment.from_loader(loader).resolve_type_names

      decls = env.declarations.select do |decl|
        loc = decl.location or raise
        # @type var name: String
        name = loc.buffer.name

        patterns.empty? || patterns.any? do |pat|
          case pat
          when Pathname
            Pathname(name).ascend.any? {|p| p == pat }
          when String
            name.end_with?(pat) || File.fnmatch(pat, name, File::FNM_EXTGLOB)
          end
        end
      end

      stdout.print JSON.generate(decls)
      stdout.flush
    end

    def run_list(args, options)
      # @type var list: Set[:class | :module | :interface]
      list = Set[]

      OptionParser.new do |opts|
        opts.banner = <<EOB
Usage: rbs list [options...]

List classes, modules, and interfaces.

Examples:

  $ rbs list
  $ rbs list --class --module --interface

Options:
EOB
        opts.on("--class", "List classes") { list << :class }
        opts.on("--module", "List modules") { list << :module }
        opts.on("--interface", "List interfaces") { list << :interface }
      end.order!(args)

      list.merge(_ = [:class, :module, :interface]) if list.empty?

      loader = options.loader()

      env = Environment.from_loader(loader).resolve_type_names

      if list.include?(:class) || list.include?(:module)
        env.class_decls.each do |name, entry|
          case entry
          when Environment::ModuleEntry
            if list.include?(:module)
              stdout.puts "#{name} (module)"
            end
          when Environment::ClassEntry
            if list.include?(:class)
              stdout.puts "#{name} (class)"
            end
          end
        end
      end

      if list.include?(:interface)
        env.interface_decls.each do |name, entry|
          stdout.puts "#{name} (interface)"
        end
      end
    end

    def run_ancestors(args, options)
      # @type var kind: :instance | :singleton
      kind = :instance

      OptionParser.new do |opts|
        opts.banner = <<EOU
Usage: rbs ancestors [options...] [type_name]

Show ancestors of the given class or module.

Examples:

  $ rbs ancestors --instance String
  $ rbs ancestors --singleton Array

Options:
EOU
        opts.on("--instance", "Ancestors of instance of the given type_name (default)") { kind = :instance }
        opts.on("--singleton", "Ancestors of singleton of the given type_name") { kind = :singleton }
      end.order!(args)

      loader = options.loader()

      env = Environment.from_loader(loader).resolve_type_names

      builder = DefinitionBuilder::AncestorBuilder.new(env: env)
      type_name = TypeName(args[0]).absolute!

      if env.class_decls.key?(type_name)
        ancestors = case kind
                    when :instance
                      builder.instance_ancestors(type_name)
                    when :singleton
                      builder.singleton_ancestors(type_name)
                    else
                      raise
                    end

        ancestors.ancestors.each do |ancestor|
          case ancestor
          when Definition::Ancestor::Singleton
            stdout.puts "singleton(#{ancestor.name})"
          when Definition::Ancestor::Instance
            if ancestor.args.empty?
              stdout.puts ancestor.name.to_s
            else
              stdout.puts "#{ancestor.name}[#{ancestor.args.join(", ")}]"
            end
          end
        end
      else
        stdout.puts "Cannot find class: #{type_name}"
      end
    end

    def run_methods(args, options)
      # @type var kind: :instance | :singleton
      kind = :instance
      inherit = true

      OptionParser.new do |opts|
        opts.banner = <<EOU
Usage: rbs methods [options...] [type_name]

Show methods defined in the class or module.

Examples:

  $ rbs methods --instance Kernel
  $ rbs methods --singleton --no-inherit String

Options:
EOU
        opts.on("--instance", "Show instance methods (default)") { kind = :instance }
        opts.on("--singleton", "Show singleton methods") { kind = :singleton }
        opts.on("--[no-]inherit", "Show methods defined in super class and mixed modules too") {|v| inherit = v }
      end.order!(args)

      unless args.size == 1
        stdout.puts "Expected one argument."
        return
      end

      loader = options.loader()

      env = Environment.from_loader(loader).resolve_type_names

      builder = DefinitionBuilder.new(env: env)
      type_name = TypeName(args[0]).absolute!

      if env.class_decls.key?(type_name)
        definition = case kind
                     when :instance
                       builder.build_instance(type_name)
                     when :singleton
                       builder.build_singleton(type_name)
                     else
                       raise
                     end

        definition.methods.keys.sort.each do |name|
          method = definition.methods[name]
          if inherit || method.implemented_in == type_name
            stdout.puts "#{name} (#{method.accessibility})"
          end
        end
      else
        stdout.puts "Cannot find class: #{type_name}"
      end
    end

    def run_method(args, options)
      # @type var kind: :instance | :singleton
      kind = :instance

      OptionParser.new do |opts|
        opts.banner = <<EOU
Usage: rbs method [options...] [type_name] [method_name]

Show the information of the method specified by type_name and method_name.

Examples:

  $ rbs method --instance Kernel puts
  $ rbs method --singleton String try_convert

Options:
EOU
        opts.on("--instance", "Show an instance method (default)") { kind = :instance }
        opts.on("--singleton", "Show a singleton method") { kind = :singleton }
      end.order!(args)

      unless args.size == 2
        stdout.puts "Expected two arguments, but given #{args.size}."
        return
      end

      loader = options.loader()
      env = Environment.from_loader(loader).resolve_type_names

      builder = DefinitionBuilder.new(env: env)
      type_name = TypeName(args[0]).absolute!
      method_name = args[1].to_sym

      unless env.class_decls.key?(type_name)
        stdout.puts "Cannot find class: #{type_name}"
        return
      end

      definition = case kind
                   when :instance
                     builder.build_instance(type_name)
                   when :singleton
                     builder.build_singleton(type_name)
                   else
                     raise
                   end

      method = definition.methods[method_name]

      unless method
        stdout.puts "Cannot find method: #{method_name}"
        return
      end

      stdout.puts "#{type_name}#{kind == :instance ? "#" : "."}#{method_name}"
      stdout.puts "  defined_in: #{method.defined_in}"
      stdout.puts "  implementation: #{method.implemented_in}"
      stdout.puts "  accessibility: #{method.accessibility}"
      stdout.puts "  types:"
      separator = " "
      for type in method.method_types
        stdout.puts "    #{separator} #{type}"
        separator = "|"
      end
    end

    def run_validate(args, options)
      OptionParser.new do |opts|
        opts.banner = <<EOU
Usage: rbs validate

Validate RBS files. It ensures the type names in RBS files are present and the type applications have correct arity.

Examples:

  $ rbs validate
EOU

        opts.on("--silent") do
          require "stringio"
          @stdout = StringIO.new
        end
      end.parse!(args)

      loader = options.loader()
      env = Environment.from_loader(loader).resolve_type_names

      builder = DefinitionBuilder.new(env: env)
      validator = Validator.new(env: env, resolver: TypeNameResolver.from_env(env))

      env.class_decls.each do |name, decl|
        stdout.puts "Validating class/module definition: `#{name}`..."
        builder.build_instance(name).each_type do |type|
          validator.validate_type type, context: [Namespace.root]
        end
        builder.build_singleton(name).each_type do |type|
          validator.validate_type type, context: [Namespace.root]
        end

        d = decl.primary.decl

        validator.validate_type_params(
          d.type_params,
          type_name: name,
          location: d.location&.aref(:type_params)
        )

        decl.decls.each do |d|
          d.decl.each_member do |member|
            case member
            when AST::Members::MethodDefinition
              validator.validate_method_definition(member, type_name: name)
            end
          end
        end
      end

      env.interface_decls.each do |name, decl|
        stdout.puts "Validating interface: `#{name}`..."
        builder.build_interface(name).each_type do |type|
          validator.validate_type type, context: [Namespace.root]
        end

        validator.validate_type_params(
          decl.decl.type_params,
          type_name: name,
          location: decl.decl.location&.aref(:type_params)
        )

        decl.decl.members.each do |member|
          case member
          when AST::Members::MethodDefinition
            validator.validate_method_definition(member, type_name: name)
          end
        end
      end

      env.constant_decls.each do |name, const|
        stdout.puts "Validating constant: `#{name}`..."
        validator.validate_type const.decl.type, context: const.context
        builder.ensure_namespace!(name.namespace, location: const.decl.location)
      end

      env.global_decls.each do |name, global|
        stdout.puts "Validating global: `#{name}`..."
        validator.validate_type global.decl.type, context: [Namespace.root]
      end

      env.alias_decls.each do |name, decl|
        stdout.puts "Validating alias: `#{name}`..."
        builder.expand_alias1(name).tap do |type|
          validator.validate_type type, context: [Namespace.root]
        end
        validator.validate_type_alias(entry: decl)
      end
    end

    def run_constant(args, options)
      # @type var context: String?
      context = nil

      OptionParser.new do |opts|
        opts.banner = <<EOU
Usage: rbs constant [options...] [name]

Resolve constant based on RBS.

Examples:

  $ rbs constant ::Object
  $ rbs constant UTF_8
  $ rbs constant --context=::Encoding UTF_8

Options:
EOU
        opts.on("--context CONTEXT", "Name of the module where the constant resolution starts") {|c| context = c }
      end.order!(args)

      unless args.size == 1
        stdout.puts "Expected one argument."
        return
      end

      loader = options.loader()
      env = Environment.from_loader(loader).resolve_type_names

      builder = DefinitionBuilder.new(env: env)
      table = ConstantTable.new(builder: builder)

      namespace = context ? Namespace.parse(context).absolute! : Namespace.root
      stdout.puts "Context: #{namespace}"
      name = Namespace.parse(args[0]).to_type_name
      stdout.puts "Constant name: #{name}"

      constant = table.resolve_constant_reference(name, context: namespace.ascend.to_a)

      if constant
        stdout.puts " => #{constant.name}: #{constant.type}"
      else
        stdout.puts " => [no constant]"
      end
    end

    def run_paths(args, options)
      OptionParser.new do |opts|
        opts.banner = <<EOU
Usage: rbs paths

Show paths to directories where the RBS files are loaded from.

Examples:

  $ rbs paths
  $ rbs -r set paths
EOU
      end.parse!(args)

      loader = options.loader()

      kind_of = -> (path) {
        # @type var path: Pathname
        case
        when path.file?
          "file"
        when path.directory?
          "dir"
        when !path.exist?
          "absent"
        else
          "unknown"
        end
      }

      loader.each_dir do |source, dir|
        case source
        when :core
          stdout.puts "#{dir} (#{kind_of[dir]}, core)"
        when Pathname
          stdout.puts "#{dir} (#{kind_of[dir]})"
        when EnvironmentLoader::Library
          stdout.puts "#{dir} (#{kind_of[dir]}, library, name=#{source.name})"
        end
      end
    end

    def run_prototype(args, options)
      format = args.shift

      case format
      when "rbi", "rb"
        run_prototype_file(format, args)
      when "runtime"
        require_libs = []
        relative_libs = []
        merge = false
        owners_included = []

        OptionParser.new do |opts|
          opts.banner = <<EOU
Usage: rbs prototype runtime [options...] [pattern...]

Generate RBS prototype based on runtime introspection.
It loads Ruby code specified in [options] and generates RBS prototypes for classes matches to [pattern].

Examples:

  $ rbs prototype runtime String
  $ rbs prototype runtime --require set Set
  $ rbs prototype runtime -R lib/rbs RBS::*

Options:
EOU
          opts.on("-r", "--require LIB", "Load library using `require`") do |lib|
            require_libs << lib
          end
          opts.on("-R", "--require-relative LIB", "Load library using `require_relative`") do |lib|
            relative_libs << lib
          end
          opts.on("--merge", "Merge generated prototype RBS with existing RBS") do
            merge = true
          end
          opts.on("--method-owner CLASS", "Generate method prototypes if the owner of the method is [CLASS]") do |klass|
            owners_included << klass
          end
        end.parse!(args)

        loader = options.loader()
        env = Environment.from_loader(loader).resolve_type_names

        require_libs.each do |lib|
          require(lib)
        end

        relative_libs.each do |lib|
          eval("require_relative(lib)", binding, "rbs")
        end

        decls = Prototype::Runtime.new(patterns: args, env: env, merge: merge, owners_included: owners_included).decls

        writer = Writer.new(out: stdout)
        writer.write decls
      else
        stdout.puts <<EOU
Usage: rbs prototype [generator...] [args...]

Generate prototype of RBS files.
Supported generators are rb, rbi, runtime.

Examples:

  $ rbs prototype rb foo.rb
  $ rbs prototype rbi foo.rbi
  $ rbs prototype runtime String
EOU
        exit 1
      end
    end

    def run_prototype_file(format, args)
      availability = unless has_parser?
                       "\n** This command does not work on this interpreter (#{RUBY_ENGINE}) **\n"
                     end

      # @type var output_dir: Pathname?
      output_dir = nil
      # @type var base_dir: Pathname?
      base_dir = nil
      # @type var force: bool
      force = false

      opts = OptionParser.new
      opts.banner = <<EOU
Usage: rbs prototype #{format} [files...]
#{availability}
Generate RBS prototype from source code.
It parses specified Ruby code and and generates RBS prototypes.

It only works on MRI because it parses Ruby code with `RubyVM::AbstractSyntaxTree`.

Examples:

  $ rbs prototype rb lib/foo.rb
  $ rbs prototype rbi sorbet/rbi/foo.rbi

You can run the tool in *batch* mode by passing `--out-dir` option.

  $ rbs prototype rb --out-dir=sig lib/foo.rb
  $ rbs prototype rbi --out-dir=sig/models --base-dir=app/models app/models
EOU

      opts.on("--out-dir=DIR", "Specify the path to save the generated RBS files") do |path|
        output_dir = Pathname(path)
      end

      opts.on("--base-dir=DIR", "Specify the path to calculate the relative path to save the generated RBS files") do |path|
        base_dir = Pathname(path)
      end

      opts.on("--force", "Overwrite existing RBS files") do
        force = true
      end

      opts.parse!(args)

      unless has_parser?
        stdout.puts "Not supported on this interpreter (#{RUBY_ENGINE})."
        exit 1
      end

      if args.empty?
        stdout.puts opts
        return nil
      end

      new_parser = -> do
        case format
        when "rbi"
          Prototype::RBI.new()
        when "rb"
          Prototype::RB.new()
        else
          raise
        end
      end

      input_paths = args.map {|arg| Pathname(arg) }

      if output_dir
        # @type var skip_paths: Array[Pathname]
        skip_paths = []

        # batch mode
        input_paths.each do |path|
          stdout.puts "Processing `#{path}`..."
          ruby_files =
            if path.file?
              [path]
            else
              path.glob("**/*.rb").sort
            end

          ruby_files.each do |file_path|
            stdout.puts "  Generating RBS for `#{file_path}`..."

            relative_path =
              if base_dir
                file_path.relative_path_from(base_dir)
              else
                if top = file_path.descend.first
                  case
                  when top == Pathname("lib")
                    file_path.relative_path_from(top)
                  when top == Pathname("app")
                    file_path.relative_path_from(top)
                  else
                    file_path
                  end
                else
                  file_path
                end
              end
            relative_path = relative_path.cleanpath()

            if relative_path.absolute? || relative_path.descend.first&.to_s == ".."
              stdout.puts "  ⚠️  Cannot write the RBS to outside of the output dir: `#{relative_path}`"
              next
            end

            output_path = (output_dir + relative_path).sub_ext(".rbs")

            parser = new_parser[]
            parser.parse file_path.read()

            if output_path.file?
              if force
                stdout.puts "    - Writing RBS to existing file `#{output_path}`..."
              else
                stdout.puts "    - Skipping existing file `#{output_path}`..."
                skip_paths << file_path
                next
              end
            else
              stdout.puts "    - Writing RBS to `#{output_path}`..."
            end

            (output_path.parent).mkpath
            output_path.open("w") do |io|
              writer = Writer.new(out: io)
              writer.write(parser.decls)
            end
          end
        end

        unless skip_paths.empty?
          stdout.puts
          stdout.puts ">>>> Skipped existing #{skip_paths.size} files. Use `--force` option to update the files."
          command = original_args.take(original_args.size - input_paths.size)

          skip_paths.take(10).each do |path|
            stdout.puts "  #{defined?(Bundler) ? "bundle exec " : ""}rbs #{Shellwords.join(command)} --force #{Shellwords.escape(path.to_s)}"
          end
          if skip_paths.size > 10
            stdout.puts "  ..."
          end
        end
      else
        # file mode
        parser = new_parser[]

        input_paths.each do |file|
          parser.parse file.read()
        end

        writer = Writer.new(out: stdout)
        writer.write parser.decls
      end
    end

    def run_vendor(args, options)
      clean = false
      vendor_dir = Pathname("vendor/sigs")

      OptionParser.new do |opts|
        opts.banner = <<-EOB
Usage: rbs vendor [options...] [gems...]

Vendor signatures in the project directory.
This command ignores the RBS loading global options, `-r` and `-I`.

Examples:

  $ rbs vendor
  $ rbs vendor --vendor-dir=sig
  $ rbs vendor --no-stdlib

Options:
        EOB

        opts.on("--[no-]clean", "Clean vendor directory (default: no)") do |v|
          clean = v
        end

        opts.on("--vendor-dir [DIR]", "Specify the directory for vendored signatures (default: vendor/sigs)") do |path|
          vendor_dir = Pathname(path)
        end
      end.parse!(args)

      stdout.puts "Vendoring signatures to #{vendor_dir}..."

      loader = options.loader()

      args.each do |gem|
        name, version = gem.split(/:/, 2)

        next unless name

        stdout.puts "  Loading library: #{name}, version=#{version}..."
        loader.add(library: name, version: version)
      end

      vendorer = Vendorer.new(vendor_dir: vendor_dir, loader: loader)

      if clean
        stdout.puts "  Deleting #{vendor_dir}..."
        vendorer.clean!
      end

      stdout.puts "  Copying RBS files..."
      vendorer.copy!
    end

    def run_parse(args, options)
      OptionParser.new do |opts|
        opts.banner = <<-EOB
Usage: rbs parse [files...]

Parse given RBS files and print syntax errors.

Examples:

  $ rbs parse sig/app/models.rbs sig/app/controllers.rbs
        EOB
      end.parse!(args)

      loader = options.loader()

      syntax_error = false
      args.each do |path|
        path = Pathname(path)
        loader.each_file(path, skip_hidden: false, immediate: true) do |file_path|
          RBS.logger.info "Parsing #{file_path}..."
          buffer = Buffer.new(content: file_path.read, name: file_path)
          Parser.parse_signature(buffer)
        rescue RBS::ParsingError => ex
          stdout.puts ex.message
          syntax_error = true
        end
      end

      exit 1 if syntax_error
    end

    def run_annotate(args, options)
      require "rbs/annotate"

      source = RBS::Annotate::RDocSource.new()
      annotator = RBS::Annotate::RDocAnnotator.new(source: source)

      preserve = true

      OptionParser.new do |opts|
        opts.banner = <<-EOB
Usage: rbs annotate [options...] [files...]

Import documents from RDoc and update RBS files.

Examples:

  $ rbs annotate stdlib/pathname/**/*.rbs

Options:
        EOB

        opts.on("--[no-]system", "Load RDoc from system (defaults to true)") {|b| source.with_system_dir = b }
        opts.on("--[no-]gems", "Load RDoc from gems (defaults to false)") {|b| source.with_gems_dir = b }
        opts.on("--[no-]site", "Load RDoc from site directory (defaults to false)") {|b| source.with_site_dir = b }
        opts.on("--[no-]home", "Load RDoc from home directory (defaults to false)") {|b| source.with_home_dir = b }
        opts.on("-d", "--dir DIRNAME", "Load RDoc from DIRNAME") {|d| source.extra_dirs << Pathname(d) }
        opts.on("--[no-]arglists", "Generate arglists section (defaults to true)") {|b| annotator.include_arg_lists = b }
        opts.on("--[no-]filename", "Include source file name in the documentation (defaults to true)") {|b| annotator.include_filename = b }
        opts.on("--[no-]preserve", "Try preserve the format of the original file (defaults to true)") {|b| preserve = b }
      end.parse!(args)

      source.load()

      args.each do |file|
        path = Pathname(file)
        if path.directory?
          Pathname.glob((path + "**/*.rbs").to_s).each do |path|
            stdout.puts "Processing #{path}..."
            annotator.annotate_file(path, preserve: preserve)
          end
        else
          stdout.puts "Processing #{path}..."
          annotator.annotate_file(path, preserve: preserve)
        end
      end
    end

    def test_opt options
      opts = []

      opts.push(*options.repos.map {|dir| "--repo #{Shellwords.escape(dir)}"})
      opts.push(*options.dirs.map {|dir| "-I #{Shellwords.escape(dir)}"})
      opts.push(*options.libs.map {|lib| "-r#{Shellwords.escape(lib)}"})

      opts.empty? ? nil : opts.join(" ")
    end

    def run_test(args, options)
      # @type var unchecked_classes: Array[String]
      unchecked_classes = []
      # @type var targets: Array[String]
      targets = []
      # @type var sample_size: String?
      sample_size = nil
      # @type var double_suite: String?
      double_suite = nil

      (opts = OptionParser.new do |opts|
        opts.banner = <<EOB
Usage: rbs [rbs options...] test [test options...] COMMAND

Examples:

  $ rbs test rake test
  $ rbs --log-level=debug test --target SomeModule::* rspec
  $ rbs test --target SomeModule::* --target AnotherModule::* --target SomeClass rake test

Options:
EOB
        opts.on("--target TARGET", "Sets the runtime test target") do |target|
          targets << target
        end

        opts.on("--sample-size SAMPLE_SIZE", "Sets the sample size") do |size|
          sample_size = size
        end

        opts.on("--unchecked-class UNCHECKED_CLASS", "Sets the class that would not be checked") do |unchecked_class|
          unchecked_classes << unchecked_class
        end

        opts.on("--double-suite DOUBLE_SUITE", "Sets the double suite in use (currently supported: rspec | minitest)") do |suite|
          double_suite = suite
        end
      end).order!(args)

      if args.length.zero?
        stdout.puts opts.help
        exit 1
      end

      # @type var env_hash: Hash[String, String?]
      env_hash = {
        'RUBYOPT' => "#{ENV['RUBYOPT']} -rrbs/test/setup",
        'RBS_TEST_OPT' => test_opt(options),
        'RBS_TEST_LOGLEVEL' => %w(DEBUG INFO WARN ERROR FATAL)[RBS.logger_level || 5] || "UNKNOWN",
        'RBS_TEST_SAMPLE_SIZE' => sample_size,
        'RBS_TEST_DOUBLE_SUITE' => double_suite,
        'RBS_TEST_UNCHECKED_CLASSES' => (unchecked_classes.join(',') unless unchecked_classes.empty?),
        'RBS_TEST_TARGET' => (targets.join(',') unless targets.empty?)
      }

      # @type var out: String
      # @type var err: String
      out, err, status = __skip__ = Open3.capture3(env_hash, *args)
      stdout.print(out)
      stderr.print(err)

      status
    end

    def run_collection(args, options)
      opts = collection_options(args)
      params = {}
      opts.order args.drop(1), into: params
      config_path = options.config_path or raise
      lock_path = Collection::Config.to_lockfile_path(config_path)

      case args[0]
      when 'install'
        unless params[:frozen]
          Collection::Config.generate_lockfile(config_path: config_path, gemfile_lock_path: Pathname('./Gemfile.lock'))
        end
        Collection::Installer.new(lockfile_path: lock_path, stdout: stdout).install_from_lockfile
      when 'update'
        # TODO: Be aware of argv to update only specified gem
        Collection::Config.generate_lockfile(config_path: config_path, gemfile_lock_path: Pathname('./Gemfile.lock'), with_lockfile: false)
        Collection::Installer.new(lockfile_path: lock_path, stdout: stdout).install_from_lockfile
      when 'init'
        if config_path.exist?
          puts "#{config_path} already exists"
          exit 1
        end

        config_path.write(<<~'YAML')
          # Download sources
          sources:
            - name: ruby/gem_rbs_collection
              remote: https://github.com/ruby/gem_rbs_collection.git
              revision: main
              repo_dir: gems

          # A directory to install the downloaded RBSs
          path: .gem_rbs_collection

          gems:
            # Skip loading rbs gem's RBS.
            # It's unnecessary if you don't use rbs as a library.
            - name: rbs
              ignore: true
        YAML
        stdout.puts "created: #{config_path}"
      when 'clean'
        unless lock_path.exist?
          puts "#{lock_path} should exist to clean"
          exit 1
        end
        Collection::Cleaner.new(lockfile_path: lock_path)
      when 'help'
        puts opts.help
      else
        puts opts.help
        exit 1
      end
    end

    def collection_options(args)
      OptionParser.new do |opts|
        opts.banner = <<~HELP
          Usage: rbs collection [install|update|init|clean|help]

          Manage RBS collection, which contains third party RBS.

          Examples:

            # Initialize the configration file
            $ rbs collection init

            # Generate the lock file and install RBSs from the lock file
            $ rbs collection install

            # Update the RBSs
            $ rbs collection update
        HELP
        opts.on('--frozen') if args[0] == 'install'
      end
    end
  end
end
