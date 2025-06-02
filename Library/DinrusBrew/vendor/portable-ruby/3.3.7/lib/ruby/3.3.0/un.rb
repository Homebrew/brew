# frozen_string_literal: false
#
# = un.rb
#
# Copyright (c) 2003 WATANABE Hirofumi <eban@ruby-lang.org>
#
# This program is free software.
# You can distribute/modify this program under the same terms of Ruby.
#
# == Utilities to replace common UNIX commands in Makefiles etc
#
# == SYNOPSIS
#
#   ruby -run -e cp -- [OPTION] SOURCE DEST
#   ruby -run -e ln -- [OPTION] TARGET LINK_NAME
#   ruby -run -e mv -- [OPTION] SOURCE DEST
#   ruby -run -e rm -- [OPTION] FILE
#   ruby -run -e mkdir -- [OPTION] DIRS
#   ruby -run -e rmdir -- [OPTION] DIRS
#   ruby -run -e install -- [OPTION] SOURCE DEST
#   ruby -run -e chmod -- [OPTION] OCTAL-MODE FILE
#   ruby -run -e touch -- [OPTION] FILE
#   ruby -run -e wait_writable -- [OPTION] FILE
#   ruby -run -e mkmf -- [OPTION] EXTNAME [OPTION]
#   ruby -run -e httpd -- [OPTION] [DocumentRoot]
#   ruby -run -e colorize -- [FILE]
#   ruby -run -e help [COMMAND]

require "fileutils"
require "optparse"

module FileUtils
  @fileutils_output = $stdout
end

# :nodoc:
def setup(options = "", *long_options)
  caller = caller_locations(1, 1)[0].label
  opt_hash = {}
  argv = []
  OptionParser.new do |o|
    options.scan(/.:?/) do |s|
      opt_name = s.delete(":").intern
      o.on("-" + s.tr(":", " ")) do |val|
        opt_hash[opt_name] = val
      end
    end
    long_options.each do |s|
      opt_name, arg_name = s.split(/(?=[\s=])/, 2)
      opt_name.delete_prefix!('--')
      s = "--#{opt_name.gsub(/([A-Z]+|[a-z])([A-Z])/, '\1-\2').downcase}#{arg_name}"
      puts "#{opt_name}=>#{s}" if $DEBUG
      opt_name = opt_name.intern
      o.on(s) do |val|
        opt_hash[opt_name] = val
      end
    end
    o.on("-v") do opt_hash[:verbose] = true end
    o.on("--help") do
      UN.help([caller])
      exit
    end
    o.order!(ARGV) do |x|
      if /[*?\[{]/ =~ x
        argv.concat(Dir[x])
      else
        argv << x
      end
    end
  end
  yield argv, opt_hash
end

##
# Copy SOURCE to DEST, or multiple SOURCE(s) to DIRECTORY
#
#   ruby -run -e cp -- [OPTION] SOURCE DEST
#
#   -p          preserve file attributes if possible
#   -r          copy recursively
#   -l          make hard link instead of copying (implies -r)
#   -v          verbose
#

def cp
  setup("prl") do |argv, options|
    cmd = "cp"
    cmd += "_r" if options.delete :r
    cmd = "cp_lr" if options.delete :l
    options[:preserve] = true if options.delete :p
    dest = argv.pop
    argv = argv[0] if argv.size == 1
    FileUtils.__send__ cmd, argv, dest, **options
  end
end

##
# Create a link to the specified TARGET with LINK_NAME.
#
#   ruby -run -e ln -- [OPTION] TARGET LINK_NAME
#
#   -s          make symbolic links instead of hard links
#   -f          remove existing destination files
#   -v          verbose
#

def ln
  setup("sf") do |argv, options|
    cmd = "ln"
    cmd += "_s" if options.delete :s
    options[:force] = true if options.delete :f
    dest = argv.pop
    argv = argv[0] if argv.size == 1
    FileUtils.__send__ cmd, argv, dest, **options
  end
end

##
# Rename SOURCE to DEST, or move SOURCE(s) to DIRECTORY.
#
#   ruby -run -e mv -- [OPTION] SOURCE DEST
#
#   -v          verbose
#

def mv
  setup do |argv, options|
    dest = argv.pop
    argv = argv[0] if argv.size == 1
    FileUtils.mv argv, dest, **options
  end
end

##
# Remove the FILE
#
#   ruby -run -e rm -- [OPTION] FILE
#
#   -f          ignore nonexistent files
#   -r          remove the contents of directories recursively
#   -v          verbose
#

def rm
  setup("fr") do |argv, options|
    cmd = "rm"
    cmd += "_r" if options.delete :r
    options[:force] = true if options.delete :f
    FileUtils.__send__ cmd, argv, **options
  end
end

##
# Create the DIR, if they do not already exist.
#
#   ruby -run -e mkdir -- [OPTION] DIR
#
#   -p          no error if existing, make parent directories as needed
#   -v          verbose
#

def mkdir
  setup("p") do |argv, options|
    cmd = "mkdir"
    cmd += "_p" if options.delete :p
    FileUtils.__send__ cmd, argv, **options
  end
end

##
# Remove the DIR.
#
#   ruby -run -e rmdir -- [OPTION] DIR
#
#   -p          remove DIRECTORY and its ancestors.
#   -v          verbose
#

def rmdir
  setup("p") do |argv, options|
    options[:parents] = true if options.delete :p
    FileUtils.rmdir argv, **options
  end
end

##
# Copy SOURCE to DEST.
#
#   ruby -run -e install -- [OPTION] SOURCE DEST
#
#   -p          apply access/modification times of SOURCE files to
#               corresponding destination files
#   -m          set permission mode (as in chmod), instead of 0755
#   -o          set owner user id, instead of the current owner
#   -g          set owner group id, instead of the current group
#   -v          verbose
#

def install
  setup("pm:o:g:") do |argv, options|
    (mode = options.delete :m) and options[:mode] = /\A\d/ =~ mode ? mode.oct : mode
    options[:preserve] = true if options.delete :p
    (owner = options.delete :o) and options[:owner] = owner
    (group = options.delete :g) and options[:group] = group
    dest = argv.pop
    argv = argv[0] if argv.size == 1
    FileUtils.install argv, dest, **options
  end
end

##
# Change the mode of each FILE to OCTAL-MODE.
#
#   ruby -run -e chmod -- [OPTION] OCTAL-MODE FILE
#
#   -v          verbose
#

def chmod
  setup do |argv, options|
    mode = argv.shift
    mode = /\A\d/ =~ mode ? mode.oct : mode
    FileUtils.chmod mode, argv, **options
  end
end

##
# Update the access and modification times of each FILE to the current time.
#
#   ruby -run -e touch -- [OPTION] FILE
#
#   -v          verbose
#

def touch
  setup do |argv, options|
    FileUtils.touch argv, **options
  end
end

##
# Wait until the file becomes writable.
#
#   ruby -run -e wait_writable -- [OPTION] FILE
#
#   -n RETRY    count to retry
#   -w SEC      each wait time in seconds
#   -v          verbose
#

def wait_writable
  setup("n:w:v") do |argv, options|
    verbose = options[:verbose]
    n = options[:n] and n = Integer(n)
    wait = (wait = options[:w]) ? Float(wait) : 0.2
    argv.each do |file|
      begin
        File.open(file, "r+b") {}
      rescue Errno::ENOENT
        break
      rescue Errno::EACCES => e
        raise if n and (n -= 1) <= 0
        if verbose
          puts e
          STDOUT.flush
        end
        sleep wait
        retry
      end
    end
  end
end

##
# Create makefile using mkmf.
#
#   ruby -run -e mkmf -- [OPTION] EXTNAME [OPTION]
#
#   -d ARGS     run dir_config
#   -h ARGS     run have_header
#   -l ARGS     run have_library
#   -f ARGS     run have_func
#   -v ARGS     run have_var
#   -t ARGS     run have_type
#   -m ARGS     run have_macro
#   -c ARGS     run have_const
#   --vendor    install to vendor_ruby
#

def mkmf
  setup("d:h:l:f:v:t:m:c:", "vendor") do |argv, options|
    require 'mkmf'
    opt = options[:d] and opt.split(/:/).each {|n| dir_config(*n.split(/,/))}
    opt = options[:h] and opt.split(/:/).each {|n| have_header(*n.split(/,/))}
    opt = options[:l] and opt.split(/:/).each {|n| have_library(*n.split(/,/))}
    opt = options[:f] and opt.split(/:/).each {|n| have_func(*n.split(/,/))}
    opt = options[:v] and opt.split(/:/).each {|n| have_var(*n.split(/,/))}
    opt = options[:t] and opt.split(/:/).each {|n| have_type(*n.split(/,/))}
    opt = options[:m] and opt.split(/:/).each {|n| have_macro(*n.split(/,/))}
    opt = options[:c] and opt.split(/:/).each {|n| have_const(*n.split(/,/))}
    $configure_args["--vendor"] = true if options[:vendor]
    create_makefile(*argv)
  end
end

##
# Run WEBrick HTTP server.
#
#   ruby -run -e httpd -- [OPTION] [DocumentRoot]
#
#   --bind-address=ADDR         address to bind
#   --port=NUM                  listening port number
#   --max-clients=MAX           max number of simultaneous clients
#   --temp-dir=DIR              temporary directory
#   --do-not-reverse-lookup     disable reverse lookup
#   --request-timeout=SECOND    request timeout in seconds
#   --http-version=VERSION      HTTP version
#   --server-name=NAME          name of the server host
#   --server-software=NAME      name and version of the server
#   --ssl-certificate=CERT      The SSL certificate file for the server
#   --ssl-private-key=KEY       The SSL private key file for the server certificate
#   -v                          verbose
#

def httpd
  setup("", "BindAddress=ADDR", "Port=PORT", "MaxClients=NUM", "TempDir=DIR",
        "DoNotReverseLookup", "RequestTimeout=SECOND", "HTTPVersion=VERSION",
        "ServerName=NAME", "ServerSoftware=NAME",
        "SSLCertificate=CERT", "SSLPrivateKey=KEY") do
    |argv, options|
    begin
      require 'webrick'
    rescue LoadError
      abort "webrick is not found. You may need to `gem install webrick` to install webrick."
    end
    opt = options[:RequestTimeout] and options[:RequestTimeout] = opt.to_i
    [:Port, :MaxClients].each do |name|
      opt = options[name] and (options[name] = Integer(opt)) rescue nil
    end
    if cert = options[:SSLCertificate]
      key = options[:SSLPrivateKey] or
        raise "--ssl-private-key option must also be given"
      require 'webrick/https'
      options[:SSLEnable] = true
      options[:SSLCertificate] = OpenSSL::X509::Certificate.new(File.read(cert))
      options[:SSLPrivateKey] = OpenSSL::PKey.read(File.read(key))
      options[:Port] ||= 8443   # HTTPS Alternate
    end
    options[:Port] ||= 8080     # HTTP Alternate
    options[:DocumentRoot] = argv.shift || '.'
    s = nil
    options[:StartCallback] = proc {
      logger = s.logger
      logger.info("To access this server, open this URL in a browser:")
      s.listeners.each do |listener|
        if options[:SSLEnable]
          addr = listener.addr
          addr[3] = "127.0.0.1" if addr[3] == "0.0.0.0"
          addr[3] = "::1" if addr[3] == "::"
          logger.info("    https://#{Addrinfo.new(addr).inspect_sockaddr}")
        else
          logger.info("    http://#{listener.connect_address.inspect_sockaddr}")
        end
      end
    }
    s = WEBrick::HTTPServer.new(options)
    shut = proc {s.shutdown}
    siglist = %w"TERM QUIT"
    siglist.concat(%w"HUP INT") if STDIN.tty?
    siglist &= Signal.list.keys
    siglist.each do |sig|
      Signal.trap(sig, shut)
    end
    s.start
  end
end

##
# Colorize ruby code.
#
#   ruby -run -e colorize -- [FILE]
#

def colorize
  begin
    require "irb/color"
  rescue LoadError
    raise "colorize requires irb 1.1.0 or later"
  end
  setup do |argv, |
    if argv.empty?
      puts IRB::Color.colorize_code STDIN.read
      return
    end
    argv.each do |file|
      puts IRB::Color.colorize_code File.read(file)
    end
  end
end

##
# Display help message.
#
#   ruby -run -e help [COMMAND]
#

def help
  setup do |argv,|
    UN.help(argv)
  end
end

module UN # :nodoc:

  VERSION = "0.3.0"

  module_function
  def help(argv, output: $stdout)
    all = argv.empty?
    cmd = nil
    if all
      store = proc {|msg| output << msg}
    else
      messages = {}
      store = proc {|msg| messages[cmd] = msg}
    end
    File.open(__FILE__) do |me|
      while me.gets("##\n")
        if help = me.gets("\n\n")
          if all or argv.include?(cmd = help[/^#\s*ruby\s.*-e\s+(\w+)/, 1])
            store[help.gsub(/^# ?/, "")]
            break unless all or argv.size > messages.size
          end
        end
      end
    end
    if messages
      argv.each {|arg| output << messages[arg]}
    end
  end
end
