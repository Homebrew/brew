require "optparse"

module TypeProf
  module CLI
    module_function

    def parse(argv)
      opt = OptionParser.new

      opt.banner = "Usage: #{ opt.program_name } [options] files..."

      output = nil

      # Verbose level:
      # * 0: none
      # * 1: default level
      # * 2: debugging level
      verbose = 1

      options = {}
      lsp_options = {}
      dir_filter = nil
      gem_rbs_features = []
      show_version = false
      max_sec = max_iter = nil
      collection_path = RBS::Collection::Config::PATH

      load_path_ext = []

      opt.separator ""
      opt.separator "Options:"
      opt.on("-o OUTFILE", "Output to OUTFILE instead of stdout") {|v| output = v }
      opt.on("-q", "--quiet", "Do not display progress indicator") { options[:show_indicator] = false }
      opt.on("-v", "--verbose", "Alias to --show-errors") { options[:show_errors] = true }
      opt.on("--version", "Display typeprof version") { show_version = true }
      opt.on("-I DIR", "Add DIR to the load/require path") {|v| load_path_ext << v }
      opt.on("-r FEATURE", "Require RBS of the FEATURE gem") {|v| gem_rbs_features << v }
      opt.on("--collection PATH", "File path of collection configuration") { |v| collection_path = v }
      opt.on("--no-collection", "Ignore collection configuration") { collection_path = nil }
      opt.on("--lsp", "LSP mode") {|v| options[:lsp] = true }

      opt.separator ""
      opt.separator "Analysis output options:"
      opt.on("--include-dir DIR", "Include the analysis result of .rb file in DIR") do |dir|
        # When `--include-dir` option is specified as the first directory option,
        # typeprof will exclude any files by default unless a file path matches the explicit option
        dir_filter ||= [[:exclude]]
        dir_filter << [:include, File.expand_path(dir)]
      end
      opt.on("--exclude-dir DIR", "Exclude the analysis result of .rb file in DIR") do |dir|
        # When `--exclude-dir` option is specified as the first directory option,
        # typeprof will include any files by default, except Ruby's install directory and Gem directories
        dir_filter ||= ConfigData::DEFAULT_DIR_FILTER
        dir_filter << [:exclude, File.expand_path(dir)]
      end
      opt.on("--exclude-untyped", "Exclude (comment out) all entries including untyped") {|v| options[:exclude_untyped] = v }
      opt.on("--[no-]show-typeprof-version", "Display TypeProf version in a header") {|v| options[:show_typeprof_version] = v }
      opt.on("--[no-]show-errors", "Display possible errors found during the analysis") {|v| options[:show_errors] = v }
      opt.on("--[no-]show-untyped", "Display \"Foo | untyped\" instead of \"Foo\"") {|v| options[:show_untyped] = v }
      opt.on("--[no-]show-parameter-names", "Display parameter names for methods") {|v| options[:show_parameter_names] = v }
      opt.on("--[no-]show-source-locations", "Display definition source locations for methods") {|v| options[:show_source_locations] = v }

      opt.separator ""
      opt.separator "Analysis limit options:"
      opt.on("--max-second SECOND", Float, "Limit the maxium time of analysis (in second)") {|v| max_sec = v }
      opt.on("--max-iteration TIMES", Integer, "Limit the maxium instruction count of analysis") {|v| max_iter = v }

      opt.separator ""
      opt.separator "Advanced options:"
      opt.on("--[no-]stub-execution", "Force to call all unreachable methods with \"untyped\" arguments") {|v| options[:stub_execution] = v }
      opt.on("--type-depth-limit DEPTH", Integer, "Limit the maximum depth of nested types") {|v| options[:type_depth_limit] = v }
      opt.on("--union-width-limit WIDTH", Integer, "Limit the maximum count of class instances in one union type") {|v| options[:union_width_limit] = v }
      opt.on("--debug", "Display analysis log (for debugging purpose)") { verbose = 2 }
      opt.on("--[no-]stackprof MODE", /\Acpu|wall|object\z/, "Enable stackprof (for debugging purpose)") {|v| options[:stackprof] = v.to_sym }

      opt.separator ""
      opt.separator "LSP options:"
      opt.on("--port PORT", Integer, "Specify a port number to listen for requests on") {|v| lsp_options[:port] = v }
      opt.on("--stdio", "Use stdio for LSP transport") {|v| lsp_options[:stdio] = v }

      opt.parse!(argv)

      $LOAD_PATH.unshift(*load_path_ext)

      dir_filter ||= ConfigData::DEFAULT_DIR_FILTER
      rb_files = []
      rbs_files = []
      argv.each do |path|
        if File.extname(path) == ".rbs"
          rbs_files << path
        else
          rb_files << path
        end
      end

      puts "typeprof #{ VERSION }" if show_version
      if rb_files.empty? && !options[:lsp]
        exit if show_version
        raise OptionParser::InvalidOption.new("no input files")
      end

      if !options[:lsp] && !lsp_options.empty?
        exit if show_version
        raise OptionParser::InvalidOption.new("lsp options with non-lsp mode")
      end

      ConfigData.new(
        rb_files: rb_files,
        rbs_files: rbs_files,
        output: output,
        gem_rbs_features: gem_rbs_features,
        collection_path: collection_path,
        verbose: verbose,
        dir_filter: dir_filter,
        max_sec: max_sec,
        max_iter: max_iter,
        options: options,
        lsp_options: lsp_options,
      )

    rescue OptionParser::InvalidOption
      puts $!
      exit
    end
  end
end
