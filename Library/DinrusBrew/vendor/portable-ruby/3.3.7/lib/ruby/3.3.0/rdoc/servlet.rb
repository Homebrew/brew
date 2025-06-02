# frozen_string_literal: true
require_relative '../rdoc'
require 'erb'
require 'time'
require 'json'

begin
  require 'webrick'
rescue LoadError
  abort "webrick is not found. You may need to `gem install webrick` to install webrick."
end

##
# This is a WEBrick servlet that allows you to browse ri documentation.
#
# You can show documentation through either `ri --server` or, with RubyGems
# 2.0 or newer, `gem server`.  For ri, the server runs on port 8214 by
# default.  For RubyGems the server runs on port 8808 by default.
#
# You can use this servlet in your own project by mounting it on a WEBrick
# server:
#
#   require 'webrick'
#
#   server = WEBrick::HTTPServer.new Port: 8000
#
#   server.mount '/', RDoc::Servlet
#
# If you want to mount the servlet some other place than the root, provide the
# base path when mounting:
#
#   server.mount '/rdoc', RDoc::Servlet, '/rdoc'

class RDoc::Servlet < WEBrick::HTTPServlet::AbstractServlet

  @server_stores = Hash.new { |hash, server| hash[server] = {} }
  @cache         = Hash.new { |hash, store|  hash[store]  = {} }

  ##
  # Maps an asset type to its path on the filesystem

  attr_reader :asset_dirs

  ##
  # An RDoc::Options instance used for rendering options

  attr_reader :options

  ##
  # Creates an instance of this servlet that shares cached data between
  # requests.

  def self.get_instance server, *options # :nodoc:
    stores = @server_stores[server]

    new server, stores, @cache, *options
  end

  ##
  # Creates a new WEBrick servlet.
  #
  # Use +mount_path+ when mounting the servlet somewhere other than /.
  #
  # Use +extra_doc_dirs+ for additional documentation directories.
  #
  # +server+ is provided automatically by WEBrick when mounting.  +stores+ and
  # +cache+ are provided automatically by the servlet.

  def initialize server, stores, cache, mount_path = nil, extra_doc_dirs = []
    super server

    @cache      = cache
    @mount_path = mount_path
    @extra_doc_dirs = extra_doc_dirs
    @stores     = stores

    @options = RDoc::Options.new
    @options.op_dir = '.'

    darkfish_dir = nil

    # HACK dup
    $LOAD_PATH.each do |path|
      darkfish_dir = File.join path, 'rdoc/generator/template/darkfish/'
      next unless File.directory? darkfish_dir
      @options.template_dir = darkfish_dir
      break
    end

    @asset_dirs = {
      :darkfish   => darkfish_dir,
      :json_index =>
        File.expand_path('../generator/template/json_index/', __FILE__),
    }
  end

  ##
  # Serves the asset at the path in +req+ for +generator_name+ via +res+.

  def asset generator_name, req, res
    asset_dir = @asset_dirs[generator_name]

    asset_path = File.join asset_dir, req.path

    if_modified_since req, res, asset_path

    res.body = File.read asset_path

    res.content_type = case req.path
                       when /\.css\z/ then 'text/css'
                       when /\.js\z/  then 'application/javascript'
                       else                'application/octet-stream'
                       end
  end

  ##
  # GET request entry point.  Fills in +res+ for the path, etc. in +req+.

  def do_GET req, res
    req.path.sub!(/\A#{Regexp.escape @mount_path}/, '') if @mount_path

    case req.path
    when '/' then
      root req, res
    when '/js/darkfish.js', '/js/jquery.js', '/js/search.js',
         %r%^/css/%, %r%^/images/%, %r%^/fonts/% then
      asset :darkfish, req, res
    when '/js/navigation.js', '/js/searcher.js' then
      asset :json_index, req, res
    when '/js/search_index.js' then
      root_search req, res
    else
      show_documentation req, res
    end
  rescue WEBrick::HTTPStatus::NotFound => e
    generator = generator_for RDoc::Store.new

    not_found generator, req, res, e.message
  rescue WEBrick::HTTPStatus::Status
    raise
  rescue => e
    error e, req, res
  end

  ##
  # Fills in +res+ with the class, module or page for +req+ from +store+.
  #
  # +path+ is relative to the mount_path and is used to determine the class,
  # module or page name (/RDoc/Servlet.html becomes RDoc::Servlet).
  # +generator+ is used to create the page.

  def documentation_page store, generator, path, req, res
    text_name = path.chomp '.html'
    name = text_name.gsub '/', '::'

    if klass = store.find_class_or_module(name) then
      res.body = generator.generate_class klass
    elsif page = store.find_text_page(name.sub(/_([^_]*)\z/, '.\1')) then
      res.body = generator.generate_page page
    elsif page = store.find_text_page(text_name.sub(/_([^_]*)\z/, '.\1')) then
      res.body = generator.generate_page page
    else
      not_found generator, req, res
    end
  end

  ##
  # Creates the JSON search index on +res+ for the given +store+.  +generator+
  # must respond to \#json_index to build.  +req+ is ignored.

  def documentation_search store, generator, req, res
    json_index = @cache[store].fetch :json_index do
      @cache[store][:json_index] =
        JSON.dump generator.json_index.build_index
    end

    res.content_type = 'application/javascript'
    res.body = "var search_data = #{json_index}"
  end

  ##
  # Returns the RDoc::Store and path relative to +mount_path+ for
  # documentation at +path+.

  def documentation_source path
    _, source_name, path = path.split '/', 3

    store = @stores[source_name]
    return store, path if store

    store = store_for source_name

    store.load_all

    @stores[source_name] = store

    return store, path
  end

  ##
  # Generates an error page for the +exception+ while handling +req+ on +res+.

  def error exception, req, res
    backtrace = exception.backtrace.join "\n"

    res.content_type = 'text/html'
    res.status = 500
    res.body = <<-BODY
<!DOCTYPE html>
<html>
<head>
<meta content="text/html; charset=UTF-8" http-equiv="Content-Type">

<title>Error - #{ERB::Util.html_escape exception.class}</title>

<link type="text/css" media="screen" href="#{@mount_path}/css/rdoc.css" rel="stylesheet">
</head>
<body>
<h1>Error</h1>

<p>While processing <code>#{ERB::Util.html_escape req.request_uri}</code> the
RDoc (#{ERB::Util.html_escape RDoc::VERSION}) server has encountered a
<code>#{ERB::Util.html_escape exception.class}</code>
exception:

<pre>#{ERB::Util.html_escape exception.message}</pre>

<p>Please report this to the
<a href="https://github.com/ruby/rdoc/issues">RDoc issues tracker</a>.  Please
include the RDoc version, the URI above and exception class, message and
backtrace.  If you're viewing a gem's documentation, include the gem name and
version.  If you're viewing Ruby's documentation, include the version of ruby.

<p>Backtrace:

<pre>#{ERB::Util.html_escape backtrace}</pre>

</body>
</html>
    BODY
  end

  ##
  # Instantiates a Darkfish generator for +store+

  def generator_for store
    generator = RDoc::Generator::Darkfish.new store, @options
    generator.file_output = false
    generator.asset_rel_path = '..'

    rdoc = RDoc::RDoc.new
    rdoc.store     = store
    rdoc.generator = generator
    rdoc.options   = @options

    @options.main_page = store.main
    @options.title     = store.title

    generator
  end

  ##
  # Handles the If-Modified-Since HTTP header on +req+ for +path+.  If the
  # file has not been modified a Not Modified response is returned.  If the
  # file has been modified a Last-Modified header is added to +res+.

  def if_modified_since req, res, path = nil
    last_modified = File.stat(path).mtime if path

    res['last-modified'] = last_modified.httpdate

    return unless ims = req['if-modified-since']

    ims = Time.parse ims

    unless ims < last_modified then
      res.body = ''
      raise WEBrick::HTTPStatus::NotModified
    end
  end

  ##
  # Returns an Array of installed documentation.
  #
  # Each entry contains the documentation name (gem name, 'Ruby
  # Documentation', etc.), the path relative to the mount point, whether the
  # documentation exists, the type of documentation (See RDoc::RI::Paths#each)
  # and the filesystem to the RDoc::Store for the documentation.

  def installed_docs
    extra_counter = 0
    ri_paths.map do |path, type|
      store = RDoc::Store.new path, type
      exists = File.exist? store.cache_path

      case type
      when :gem then
        gem_path = path[%r%/([^/]*)/ri$%, 1]
        [gem_path, "#{gem_path}/", exists, type, path]
      when :system then
        ['Ruby Documentation', 'ruby/', exists, type, path]
      when :site then
        ['Site Documentation', 'site/', exists, type, path]
      when :home then
        ['Home Documentation', 'home/', exists, type, path]
      when :extra then
        extra_counter += 1
        store.load_cache if exists
        title = store.title || "Extra Documentation"
        [title, "extra-#{extra_counter}/", exists, type, path]
      end
    end
  end

  ##
  # Returns a 404 page built by +generator+ for +req+ on +res+.

  def not_found generator, req, res, message = nil
    message ||= "The page <kbd>#{ERB::Util.h req.path}</kbd> was not found"
    res.body = generator.generate_servlet_not_found message
    res.status = 404
  end

  ##
  # Enumerates the ri paths.  See RDoc::RI::Paths#each

  def ri_paths &block
    RDoc::RI::Paths.each true, true, true, :all, *@extra_doc_dirs, &block #TODO: pass extra_dirs
  end

  ##
  # Generates the root page on +res+.  +req+ is ignored.

  def root req, res
    generator = RDoc::Generator::Darkfish.new nil, @options

    res.body = generator.generate_servlet_root installed_docs

    res.content_type = 'text/html'
  end

  ##
  # Generates a search index for the root page on +res+.  +req+ is ignored.

  def root_search req, res
    search_index = []
    info         = []

    installed_docs.map do |name, href, exists, type, path|
      next unless exists

      search_index << name

      case type
      when :gem
        gemspec = path.gsub(%r%/doc/([^/]*?)/ri$%,
                            '/specifications/\1.gemspec')

        spec = Gem::Specification.load gemspec

        path    = spec.full_name
        comment = spec.summary
      when :system then
        path    = 'ruby'
        comment = 'Documentation for the Ruby standard library'
      when :site then
        path    = 'site'
        comment = 'Documentation for non-gem libraries'
      when :home then
        path    = 'home'
        comment = 'Documentation from your home directory'
      when :extra
        comment = name
      end

      info << [name, '', path, '', comment]
    end

    index = {
      :index => {
        :searchIndex     => search_index,
        :longSearchIndex => search_index,
        :info            => info,
      }
    }

    res.body = "var search_data = #{JSON.dump index};"
    res.content_type = 'application/javascript'
  end

  ##
  # Displays documentation for +req+ on +res+, whether that be HTML or some
  # asset.

  def show_documentation req, res
    store, path = documentation_source req.path

    if_modified_since req, res, store.cache_path

    generator = generator_for store

    case path
    when nil, '', 'index.html' then
      res.body = generator.generate_index
    when 'table_of_contents.html' then
      res.body = generator.generate_table_of_contents
    when 'js/search_index.js' then
      documentation_search store, generator, req, res
    else
      documentation_page store, generator, path, req, res
    end
  ensure
    res.content_type ||= 'text/html'
  end

  ##
  # Returns an RDoc::Store for the given +source_name+ ('ruby' or a gem name).

  def store_for source_name
    case source_name
    when 'home' then
      RDoc::Store.new RDoc::RI::Paths.home_dir, :home
    when 'ruby' then
      RDoc::Store.new RDoc::RI::Paths.system_dir, :system
    when 'site' then
      RDoc::Store.new RDoc::RI::Paths.site_dir, :site
    when /\Aextra-(\d+)\z/ then
      index = $1.to_i - 1
      ri_dir = installed_docs[index][4]
      RDoc::Store.new ri_dir, :extra
    else
      ri_dir, type = ri_paths.find do |dir, dir_type|
        next unless dir_type == :gem

        source_name == dir[%r%/([^/]*)/ri$%, 1]
      end

      raise WEBrick::HTTPStatus::NotFound,
            "Could not find gem \"#{ERB::Util.html_escape(source_name)}\". Are you sure you installed it?" unless ri_dir

      store = RDoc::Store.new ri_dir, type

      return store if File.exist? store.cache_path

      raise WEBrick::HTTPStatus::NotFound,
            "Could not find documentation for \"#{ERB::Util.html_escape(source_name)}\". Please run `gem rdoc --ri gem_name`"

    end
  end

end
