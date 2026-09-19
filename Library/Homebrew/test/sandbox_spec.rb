# typed: true
# frozen_string_literal: true

require "sandbox"
require "securerandom"

RSpec.describe Sandbox, :needs_macos do
  subject(:sandbox) { described_class.new }

  let(:dir) { mktmpdir }
  let(:file) { dir/"foo" }

  define_negated_matcher :not_matching, :matching

  before do
    skip "Sandbox not implemented." unless described_class.available?
    if described_class.nested_sandbox? && !RSpec.current_example&.metadata&.key?(:no_sandbox_run)
      skip "Nested sandboxing is not supported."
    end
  end

  describe "#seatbelt_profile", :no_sandbox_run do
    subject(:sandbox) do
      Class.new(described_class) do
        T.bind(self, T.class_of(Sandbox))
        public :seatbelt_profile
      end.new
    end

    it "keeps the per-user system temporary directories writable without the download cache" do
      sandbox.allow_write_system_temp
      allow_paths = sandbox.profile.rules.select { |rule| rule.operation == "file-write*" }
                           .map { |rule| rule.filter&.path }
      expect(allow_paths).to include("^/private/var/folders/[^/]+/[^/]+/[C,T]/")
      expect(allow_paths).not_to include(HOMEBREW_CACHE.to_s)
    end

    it "restricts macOS services even when network access is allowed" do
      expect(sandbox.seatbelt_profile).to include(
        "(deny mach-lookup)", "(deny lsopen)", "(deny appleevent-send)",
        "(deny network-outbound (to unix-socket))",
        '(allow network-outbound (to unix-socket (path-literal "/private/var/run/mDNSResponder")))'
      )
    end

    it "does not allow the DNS socket when network access is denied" do
      sandbox.deny_all_network
      sandbox.allow_network path: dir, type: :subpath
      expect(sandbox.seatbelt_profile).not_to include("mDNSResponder")
    end

    it "explicitly allows outbound access to a permitted socket" do
      sandbox.deny_all_network
      sandbox.allow_network path: file

      expect(sandbox.seatbelt_profile).to include("(allow network* network-outbound (literal \"#{file}\"))")
    end

    it "explicitly allows outbound access within a permitted socket directory" do
      sandbox.deny_all_network
      sandbox.allow_network path: dir, type: :subpath

      expect(sandbox.seatbelt_profile).to include("(allow network* network-outbound (subpath \"#{dir}\"))")
    end

    it "allows installed Metal Toolchain discovery when network access is denied" do
      sandbox.deny_all_network

      expect(sandbox.seatbelt_profile).to include('(global-name "com.apple.mobileassetd.v2")')
    end

    it "allows runtime Metal compilation when network access is denied" do
      sandbox.deny_all_network

      expect(sandbox.seatbelt_profile).to include('(xpc-service-name "com.apple.MTLCompilerService")')
    end

    it "allows process discovery when network access is denied" do
      sandbox.deny_all_network

      expect(sandbox.seatbelt_profile).to include('(global-name "com.apple.sysmond")')
    end

    it "allows icon type lookup when network access is denied" do
      sandbox.deny_all_network

      expect(sandbox.seatbelt_profile).to include('(global-name "com.apple.lsd.mapdb")')
    end
  end

  describe "#sandbox_command", :no_sandbox_run do
    subject(:sandbox) do
      Class.new(described_class) do
        T.bind(self, T.class_of(Sandbox))
        public :sandbox_command, :seatbelt_profile
      end.new
    end

    it "passes the profile directly to sandbox-exec" do
      expect(sandbox.sandbox_command(["/bin/echo", "hello world"], dir.to_s))
        .to eq(["/usr/bin/sandbox-exec", "-p", sandbox.seatbelt_profile, "/bin/echo", "hello world"])
    end
  end

  describe ".avoid_nested_sandboxing?", :no_sandbox_run do
    before do
      allow(Homebrew::EnvConfig).to receive(:avoid_nested_sandboxing?).and_return(true)
      allow(described_class).to receive(:nested_sandbox?).and_return(true)
      allow(Homebrew).to receive(:default_prefix?).and_return(false)
      allow(Process).to receive(:groups).and_return([])
    end

    it "skips the sandbox for an unprivileged user in a custom prefix" do
      expect(described_class.avoid_nested_sandboxing?).to be(true)
    end

    it "is false when not opted in via the environment" do
      allow(Homebrew::EnvConfig).to receive(:avoid_nested_sandboxing?).and_return(false)
      expect(described_class.avoid_nested_sandboxing?).to be(false)
    end

    it "is false when not running inside another sandbox" do
      allow(described_class).to receive(:nested_sandbox?).and_return(false)
      expect(described_class.avoid_nested_sandboxing?).to be(false)
    end

    it "errors out in the default prefix" do
      allow(Homebrew).to receive(:default_prefix?).and_return(true)
      expect { described_class.avoid_nested_sandboxing? }.to raise_error(SystemExit)
    end

    it "errors out for a user in a privileged group" do
      allow(Process).to receive(:groups).and_return([Etc.getgrnam("staff")&.gid].compact)
      expect { described_class.avoid_nested_sandboxing? }.to raise_error(SystemExit)
    end
  end

  specify "#allow_write" do
    sandbox.allow_write path: file
    sandbox.run "touch", file

    expect(file).to exist
  end

  it "writes to a path containing the seatbelt string delimiters \\ and \"" do
    delimiter_dir = dir/"I:\\ and \"quote\""
    delimiter_dir.mkpath
    target = delimiter_dir/"foo"
    sandbox.allow_write path: target
    sandbox.run "touch", target

    expect(target).to exist
  end

  describe "#run" do
    let(:gpgme_test_home) { Pathname("gpgme-20260911-52880-n7d0ah/gpgme-2.2.0/tests/gpg") }

    let(:handlers_for_scheme) do
      lambda do |scheme|
        SystemCommand.run!("/usr/bin/osascript", args: ["-l", "JavaScript", "-e", <<~JS, scheme]).stdout
          ObjC.import('CoreServices');
          function run(argv) {
            return JSON.stringify(ObjC.deepUnwrap(ObjC.castRefToObject($.LSCopyAllHandlersForURLScheme($(argv[0])))) || []);
          }
        JS
      end
    end

    it "denies connections to Unix sockets in writable directories" do
      UNIXServer.open(file) do
        UNIXSocket.open(file, &:close)
        sandbox.allow_write_path(dir)

        expect do
          sandbox.run RbConfig.ruby, "-rsocket", "-e", "UNIXSocket.open(ARGV.fetch(0), &:close)", file
        end.to raise_error(ErrorDuringExecution)
      end
    end

    it "denies datagrams to Unix sockets in writable directories" do
      server = Socket.new(Socket::AF_UNIX, Socket::SOCK_DGRAM)
      server.bind(Socket.sockaddr_un(file.to_s))
      sandbox.allow_write_path(dir)

      expect do
        sandbox.run RbConfig.ruby, "-rsocket", "-e", <<~RUBY, file
          Socket.open(:UNIX, :DGRAM) { |socket| socket.send("test", 0, Socket.sockaddr_un(ARGV.fetch(0))) }
        RUBY
      end.to raise_error(ErrorDuringExecution)
    ensure
      server&.close
    end

    it "allows explicitly permitted Unix sockets when network access is denied" do
      UNIXServer.open(file) do
        sandbox.deny_all_network
        sandbox.allow_network path: file

        expect do
          sandbox.run RbConfig.ruby, "-rsocket", "-e", "UNIXSocket.open(ARGV.fetch(0), &:close)", file
        end.not_to raise_error
      end
    end

    it "allows the child error socket when network access is denied" do
      sandbox.deny_all_network

      expect do
        sandbox.run RbConfig.ruby, "-rsocket", "-e", <<~RUBY
          UNIXSocket.open(ENV.fetch("HOMEBREW_ERROR_PIPE")) { |socket| socket.recv_io.close }
        RUBY
      end.not_to raise_error
    end

    it "allows Unix sockets in a permitted directory when network access is denied" do
      (dir/"sockets").mkpath
      UNIXServer.open(dir/"sockets/test.sock") do
        sandbox.deny_all_network
        sandbox.allow_network path: dir, type: :subpath

        expect do
          sandbox.run RbConfig.ruby, "-rsocket", "-e", "UNIXSocket.open(ARGV.fetch(0), &:close)",
                      dir/"sockets/test.sock"
        end.not_to raise_error
      end
    end

    it "runs a private Unix socket task host online and offline" do
      expect do
        [true, false].each do |network_access_allowed|
          sandbox.deny_all_network unless network_access_allowed
          sandbox.run RbConfig.ruby, "-rsocket", "-rtimeout", "-e", <<~'RUBY'
            Dir.chdir(ENV.fetch("TMPDIR"))
            Dir.mkdir("sockets")
            UNIXServer.open("sockets/CoreFxPipe_task") do |server|
              pid = fork do
                Timeout.timeout(5) do
                  client = server.accept
                  client.write(client.gets.upcase)
                  client.close
                end
              end
              begin
                Timeout.timeout(5) do
                  UNIXSocket.open("sockets/CoreFxPipe_task") do |client|
                    client.sendmsg("query\n")
                    abort "Unexpected service response" unless client.gets == "QUERY\n"
                  end
                end
              ensure
                Process.wait(pid)
              end
              abort "Service failed" unless $?.success?
            end
            File.unlink("sockets/CoreFxPipe_task")
            Dir.rmdir("sockets")
          RUBY
        end
      end.not_to raise_error
    end

    it "connects to a private GnuPG agent at the gpgme build path when network access is denied" do
      gpgconf = which("gpgconf", ENV.fetch("HOMEBREW_PATH"))
      gpg_connect_agent = which("gpg-connect-agent", ENV.fetch("HOMEBREW_PATH"))
      skip "GnuPG not installed." if !gpgconf || !gpg_connect_agent

      # libassuan limits absolute Unix socket paths to 102 bytes on macOS.
      stub_const("HOMEBREW_TEMP", Pathname("/private/tmp"))
      sandbox.deny_all_network

      expect do
        sandbox.run RbConfig.ruby, "-rfileutils", "-e", <<~RUBY, gpgconf, gpg_connect_agent, gpgme_test_home
          home = File.join(ENV.fetch("TMPDIR"), ARGV.fetch(2))
          FileUtils.mkdir_p(home, mode: 0700)
          ENV["GNUPGHOME"] = home
          begin
            abort "Agent connection failed" unless system(ARGV.fetch(1), "GETINFO pid", "/bye")
          ensure
            system(ARGV.fetch(0), "--kill", "all")
          end
        RUBY
      end.not_to raise_error
    end

    it "keeps gpgme's private Unix socket paths within libassuan's macOS limit" do
      stub_const("HOMEBREW_TEMP", Pathname("/private/tmp"))
      sandbox.deny_all_network

      expect do
        sandbox.run RbConfig.ruby, "-rfileutils", "-rsocket", "-e", <<~'RUBY', gpgme_test_home
          socket = File.join(ENV.fetch("TMPDIR"), ARGV.fetch(0), "S.gpg-agent.browser")
          abort "Socket path exceeds libassuan's macOS limit: #{socket.bytesize} bytes" if socket.bytesize > 102
          FileUtils.mkdir_p(File.dirname(socket), mode: 0700)
          UNIXServer.open(socket, &:close)
        RUBY
      end.not_to raise_error
    end

    it "allows a private datagram service when network access is denied" do
      sandbox.allow_write_path(dir)
      sandbox.deny_all_network
      sandbox.allow_network path: dir, type: :subpath

      expect do
        sandbox.run RbConfig.ruby, "-rsocket", "-rtimeout", "-e", <<~RUBY, file
          Socket.open(:UNIX, :DGRAM) do |server|
            server.bind(Socket.sockaddr_un(ARGV.fetch(0)))
            Socket.open(:UNIX, :DGRAM) do |client|
              client.connect(Socket.sockaddr_un(ARGV.fetch(0)))
              client.send("message", 0)
              Timeout.timeout(5) { abort "Unexpected datagram" unless server.recv(64) == "message" }
            end
          end
          File.unlink(ARGV.fetch(0))
        RUBY
      end.not_to raise_error
    end

    it "allows HTTP over a private Unix socket when network access is denied" do
      sandbox.allow_write_path(dir)
      sandbox.deny_all_network
      sandbox.allow_network path: dir, type: :subpath

      expect do
        sandbox.run RbConfig.ruby, "-rsocket", "-rtimeout", "-e", <<~'RUBY', file
          UNIXServer.open(ARGV.fetch(0)) do |server|
            pid = fork do
              Timeout.timeout(10) do
                client = server.accept
                loop { break if client.gets == "\r\n" }
                client.write("HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nOK")
                client.close
              end
            end
            begin
              response = IO.popen(["/usr/bin/curl", "--fail", "--silent", "--show-error", "--max-time", "5",
                                   "--noproxy", "*", "--unix-socket", ARGV.fetch(0), "http://localhost/"], &:read)
              abort "Unexpected HTTP response" unless $?.success? && response == "OK"
            ensure
              Process.wait(pid)
            end
            abort "HTTP service failed" unless $?.success?
          end
          File.unlink(ARGV.fetch(0))
        RUBY
      end.not_to raise_error
    end

    it "denies Unix sockets outside a permitted directory" do
      (dir/"sockets").mkpath
      UNIXServer.open(file) do
        sandbox.allow_network path: dir/"sockets", type: :subpath

        expect do
          sandbox.run RbConfig.ruby, "-rsocket", "-e", "UNIXSocket.open(ARGV.fetch(0), &:close)", file
        end.to raise_error(ErrorDuringExecution)
      end
    end

    it "denies symlinks to Unix sockets outside a permitted directory" do
      (dir/"sockets").mkpath
      UNIXServer.open(file) do
        (dir/"sockets/test.sock").make_symlink(file)
        UNIXSocket.open(dir/"sockets/test.sock", &:close)
        sandbox.allow_network path: dir/"sockets", type: :subpath

        expect do
          sandbox.run RbConfig.ruby, "-rsocket", "-e", "UNIXSocket.open(ARGV.fetch(0), &:close)",
                      dir/"sockets/test.sock"
        end.to raise_error(ErrorDuringExecution)
      end
    end

    it "denies hard links to Unix sockets outside a permitted directory" do
      (dir/"sockets").mkpath
      UNIXServer.open(file) do
        File.link(file, dir/"sockets/test.sock")
        UNIXSocket.open(dir/"sockets/test.sock", &:close)
        sandbox.allow_network path: dir/"sockets", type: :subpath

        expect do
          sandbox.run RbConfig.ruby, "-rsocket", "-e", "UNIXSocket.open(ARGV.fetch(0), &:close)",
                      dir/"sockets/test.sock"
        end.to raise_error(ErrorDuringExecution)
      end
    end

    it "allows TCP connections when network access is allowed" do
      server = TCPServer.new("127.0.0.1", 0)
      expect do
        sandbox.run RbConfig.ruby, "-rsocket", "-e", <<~RUBY, server.addr[1].to_s
          TCPSocket.open("127.0.0.1", ARGV.fetch(0).to_i, &:close)
        RUBY
      end.not_to raise_error
    ensure
      server&.close
    end

    it "allows DNS resolution when network access is allowed", :needs_network do
      expect do
        sandbox.run RbConfig.ruby, "-rsocket", "-e", 'Socket.getaddrinfo("formulae.brew.sh", 443)'
      end.not_to raise_error
    end

    it "allows HTTPS downloads in network-enabled install hooks", :needs_network do
      sandbox.add_install_hook_rules(network_access_allowed: true)

      expect do
        sandbox.run "/usr/bin/curl", "--fail", "--silent", "--show-error", "--max-time", "15",
                    "--output", file, "https://formulae.brew.sh/api/formula/hello.json"
      end.not_to raise_error
    end

    it "allows extended attribute changes in offline install hooks" do
      file.write("test")
      sandbox.add_install_hook_rules(network_access_allowed: false)

      expect do
        sandbox.run "/bin/sh", "-ec", <<~SH, "--", file
          /usr/bin/xattr -wx com.apple.FinderInfo 5445535400000000000000000000000000000000000000000000000000000000 "$1"
          /usr/bin/xattr -d com.apple.FinderInfo "$1"
        SH
      end.not_to raise_error
    end

    it "discovers the installed Metal compiler without using the xcrun cache" do
      unless SystemCommand.run("/usr/bin/xcrun",
                               args: ["--no-cache", "--sdk", "macosx", "metal", "--version"]).success?
        skip "Metal Toolchain not installed."
      end

      sandbox.allow_write_temp_and_cache
      sandbox.allow_write_xcode
      sandbox.deny_read_home
      sandbox.deny_all_network

      expect do
        sandbox.run "/usr/bin/xcrun", "--no-cache", "--sdk", "macosx", "metal", "--version"
      end.not_to raise_error
    end

    it "compiles a fresh Metal kernel when network access is denied" do
      SystemCommand.run!("/usr/bin/clang", args: [
        "-fobjc-arc", "-framework", "Foundation", "-framework", "Metal", fixture("metal.m"), "-o", file
      ])
      control = SystemCommand.run(file)
      skip "Metal device not available." if control.exit_status == 77

      control.assert_success!
      sandbox.allow_write_temp_and_cache
      sandbox.deny_read_home
      sandbox.deny_all_network

      expect { sandbox.run file }.not_to raise_error
    end

    it "allows pgrep to find a child process when network access is denied" do
      sandbox.deny_all_network

      expect do
        sandbox.run RbConfig.ruby, "-e", <<~RUBY
          pid = spawn "/bin/sleep", "10"
          begin
            output = IO.popen(["/usr/bin/pgrep", "-P", Process.pid.to_s], &:read)
            abort "Child process not found" unless $?.success? && output.lines.map(&:to_i).include?(pid)
          ensure
            Process.kill("TERM", pid)
            Process.wait(pid)
          end
        RUBY
      end.not_to raise_error
    end

    it "converts an iconset when network access is denied" do
      SystemCommand.run!("/usr/bin/iconutil", args: [
        "-c", "iconset",
        "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/GenericApplicationIcon.icns",
        "-o", dir/"Test.iconset"
      ])
      sandbox.allow_write_temp_and_cache
      sandbox.deny_all_network
      sandbox.run "/usr/bin/iconutil", "-c", "icns", dir/"Test.iconset", "-o", dir/"Test.icns"

      expect(dir/"Test.icns").to exist
    end

    it "reports an empty array for an unregistered URL scheme" do
      expect(handlers_for_scheme.call("org.homebrew.sandbox-#{SecureRandom.uuid}")).to eq("[]\n")
    end

    it "reports registered HTTP URL handlers" do
      expect(JSON.parse(handlers_for_scheme.call("http"))).not_to be_empty
    end

    it "prevents LaunchServices from launching an application outside the sandbox" do
      app = dir/"SandboxTest.app"
      SystemCommand.run!("/usr/bin/osacompile", args: ["-o", app, "-e", "return"])
      SystemCommand.run!("/usr/bin/open", args: ["-W", "-n", app])
      sandbox.allow_write_temp_and_cache

      expect { sandbox.run "/usr/bin/open", "-W", "-n", app }.to raise_error(ErrorDuringExecution)
    end

    it "prevents LaunchServices from registering a URL handler" do
      lsregister = "/System/Library/Frameworks/CoreServices.framework/Frameworks/" \
                   "LaunchServices.framework/Support/lsregister"
      identifier = "org.homebrew.sandbox-#{SecureRandom.uuid}"

      # LaunchServices does not register applications under /private/tmp.
      Dir.mktmpdir("homebrew-sandbox", "#{Dir.home(ENV.fetch("USER"))}/Library/Caches") do |cache|
        app = Pathname(cache)/"SandboxTest.app"
        SystemCommand.run!("/usr/bin/osacompile", args: ["-o", app, "-e", "return"])
        SystemCommand.run!("/usr/bin/plutil", args: [
          "-replace", "CFBundleIdentifier", "-string", identifier, app/"Contents/Info.plist"
        ])
        SystemCommand.run!("/usr/bin/plutil", args: [
          "-insert", "CFBundleURLTypes", "-json", [{ CFBundleURLSchemes: [identifier] }].to_json,
          app/"Contents/Info.plist"
        ])
        sandbox.allow_write_temp_and_cache
        sandbox.allow_write_path(cache)

        # lsregister's exit status does not indicate whether registration succeeded.
        sandbox.run "/bin/sh", "-c", '"$@"; exit 0', "--", lsregister, "-f", app
        expect(handlers_for_scheme.call(identifier)).to eq("[]\n")

        SystemCommand.run!(lsregister, args: ["-f", app])
        expect(handlers_for_scheme.call(identifier)).to include(identifier)
      ensure
        SystemCommand.run(lsregister, args: ["-u", app]) if app
      end
    end

    it "fails when writing to file not specified with ##allow_write" do
      expect do
        sandbox.run "touch", file
      end.to raise_error(ErrorDuringExecution)

      expect(file).not_to exist
    end

    it "complains on failure" do
      ENV["HOMEBREW_VERBOSE"] = "1"

      allow(Utils).to receive(:popen_read).and_call_original
      allow(Utils).to receive(:popen_read).with("syslog", any_args).and_return("foo")

      expect { sandbox.run "false" }
        .to raise_error(ErrorDuringExecution)
        .and output(/foo/).to_stdout
    end

    it "does not raise getcwd EPERM when the parent CWD is sandbox-denied" do
      mktmpdir do |denied|
        sandbox.deny_read_path(denied)
        Dir.chdir(denied) do
          expect { sandbox.run "/bin/pwd" }.not_to raise_error
        end
      end
    end

    it "ignores bogus Python error" do
      ENV["HOMEBREW_VERBOSE"] = "1"

      with_bogus_error = <<~EOS
        foo
        Mar 17 02:55:06 sandboxd[342]: Python(49765) deny file-write-unlink /System/Library/Frameworks/Python.framework/Versions/2.7/lib/python2.7/distutils/errors.pyc
        bar
      EOS
      allow(Utils).to receive(:popen_read).and_call_original
      allow(Utils).to receive(:popen_read).with("syslog", any_args).and_return(with_bogus_error)

      expect { sandbox.run "false" }
        .to raise_error(ErrorDuringExecution)
        .and output(a_string_matching(/foo/).and(matching(/bar/).and(not_matching(/Python/)))).to_stdout
    end
  end

  describe "#disallow chmod on some directory" do
    it "formula does a chmod to opt" do
      expect { sandbox.run "chmod", "ug-w", HOMEBREW_PREFIX }.to raise_error(ErrorDuringExecution)
    end

    it "allows chmod on a path allowed to write" do
      mktmpdir do |path|
        FileUtils.touch path/"foo"
        sandbox.allow_write_path(path)
        expect { sandbox.run "chmod", "ug-w", path/"foo" }.not_to raise_error
      end
    end
  end

  describe "#disallow chmod SUID or SGID on some directory" do
    it "formula does a chmod 4000 to opt" do
      expect { sandbox.run "chmod", "4000", HOMEBREW_PREFIX }.to raise_error(ErrorDuringExecution)
    end

    it "allows chmod 4000 on a path allowed to write" do
      mktmpdir do |path|
        FileUtils.touch path/"foo"
        sandbox.allow_write_path(path)
        expect { sandbox.run "chmod", "4000", path/"foo" }.not_to raise_error
      end
    end
  end

  describe "#allow_write_xcode" do
    let(:home) { mktmpdir }

    before do
      allow(Dir).to receive(:home).with(ENV.fetch("USER")).and_return(home)
    end

    it "allows writing to directories used by Xcode" do
      developer = (home/"Library/Developer").mkpath
      swiftpm = (home/"Library/Caches/org.swift.swiftpm").mkpath

      sandbox.allow_write_xcode

      allow_rules = sandbox.profile.rules.select { |rule| rule.operation == "file-write*" }
      allow_paths = allow_rules.map { |rule| rule.filter&.path }
      expect(allow_paths).to eq [
        developer.to_s,
        swiftpm.to_s,
        "^/private/var/folders/[^/]+/[^/]+/T/xcrun_db(-[^/]+)?$",
      ]

      # Skipping xcrun_db regex as we cannot mock the path
      expect { sandbox.run "touch", developer/"foo" }.not_to raise_error
      expect { sandbox.run "touch", swiftpm/"foo" }.not_to raise_error
      expect { sandbox.run "touch", home/"foo" }.to raise_error(ErrorDuringExecution)
    end
  end
end
