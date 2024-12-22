# frozen_string_literal: true

require "formula"
require "service"

RSpec.describe Homebrew::Service do
  let(:name) { "formula_name" }

  def stub_formula(&block)
    formula(name) do
      url "https://brew.sh/test-1.0.tbz"

      instance_eval(&block) if block
    end
  end

  def stub_formula_with_service_sockets(sockets_var)
    stub_formula do
      service do
        run opt_bin/"beanstalkd"
        sockets sockets_var
      end
    end
  end

  describe "#std_service_path_env" do
    it "returns valid std_service_path_env" do
      f = stub_formula do
        service do
          run opt_bin/"beanstalkd"
          run_type :immediate
          environment_variables PATH: std_service_path_env
          error_log_path var/"log/beanstalkd.error.log"
          log_path var/"log/beanstalkd.log"
          working_dir var
          keep_alive true
        end
      end

      path = f.service.std_service_path_env
      expect(path).to eq("#{HOMEBREW_PREFIX}/bin:#{HOMEBREW_PREFIX}/sbin:/usr/bin:/bin:/usr/sbin:/sbin")
    end
  end

  describe "#process_type" do
    it "throws for unexpected type" do
      f = stub_formula do
        service do
          run opt_bin/"beanstalkd"
          process_type :cow
        end
      end

      expect do
        f.service.manual_command
      end.to raise_error TypeError, "Service#process_type allows: 'background'/'standard'/'interactive'/'adaptive'"
    end
  end

  describe "#keep_alive" do
    it "throws for unexpected keys" do
      f = stub_formula do
        service do
          run opt_bin/"beanstalkd"
          keep_alive test: "key"
        end
      end

      expect do
        f.service.manual_command
      end.to raise_error TypeError, "Service#keep_alive allows only [:always, :successful_exit, :crashed, :path]"
    end
  end

  describe "#requires_root?" do
    it "returns status when set" do
      f = stub_formula do
        service do
          run opt_bin/"beanstalkd"
          require_root true
        end
      end

      expect(f.service.requires_root?).to be(true)
    end

    it "returns status when not set" do
      f = stub_formula do
        service do
          run opt_bin/"beanstalkd"
        end
      end

      expect(f.service.requires_root?).to be(false)
    end
  end

  describe "#run_type" do
    it "throws for unexpected type" do
      f = stub_formula do
        service do
          run opt_bin/"beanstalkd"
          run_type :cow
        end
      end

      expect do
        f.service.manual_command
      end.to raise_error TypeError, "Service#run_type allows: 'immediate'/'interval'/'cron'"
    end
  end

  describe "#sockets" do
    let(:sockets_type_error_message) { "Service#sockets a formatted socket definition as <type>://<host>:<port>" }

    it "throws for missing type" do
      [
        stub_formula_with_service_sockets("127.0.0.1:80"),
        stub_formula_with_service_sockets({ socket: "127.0.0.1:80" }),
      ].each do |f|
        expect { f.service.manual_command }.to raise_error TypeError, sockets_type_error_message
      end
    end

    it "throws for missing host" do
      [
        stub_formula_with_service_sockets("tcp://:80"),
        stub_formula_with_service_sockets({ socket: "tcp://:80" }),
      ].each do |f|
        expect { f.service.manual_command }.to raise_error TypeError, sockets_type_error_message
      end
    end

    it "throws for missing port" do
      [
        stub_formula_with_service_sockets("tcp://127.0.0.1"),
        stub_formula_with_service_sockets({ socket: "tcp://127.0.0.1" }),
      ].each do |f|
        expect { f.service.manual_command }.to raise_error TypeError, sockets_type_error_message
      end
    end

    it "throws for invalid host" do
      [
        stub_formula_with_service_sockets("tcp://300.0.0.1:80"),
        stub_formula_with_service_sockets({ socket: "tcp://300.0.0.1:80" }),
      ].each do |f|
        expect do
          f.service.manual_command
        end.to raise_error TypeError, "Service#sockets expects a valid ipv4 or ipv6 host address"
      end
    end
  end

  describe "#manual_command" do
    it "returns valid manual_command" do
      f = stub_formula do
        service do
          run "#{HOMEBREW_PREFIX}/bin/beanstalkd"
          run_type :immediate
          environment_variables PATH: std_service_path_env, ETC_DIR: etc/"beanstalkd"
          error_log_path var/"log/beanstalkd.error.log"
          log_path var/"log/beanstalkd.log"
          working_dir var
          keep_alive true
        end
      end

      path = f.service.manual_command
      expect(path).to eq("ETC_DIR=\"#{HOMEBREW_PREFIX}/etc/beanstalkd\" #{HOMEBREW_PREFIX}/bin/beanstalkd")
    end

    it "returns valid manual_command without variables" do
      f = stub_formula do
        service do
          run opt_bin/"beanstalkd"
          run_type :immediate
          environment_variables PATH: std_service_path_env
          error_log_path var/"log/beanstalkd.error.log"
          log_path var/"log/beanstalkd.log"
          working_dir var
          keep_alive true
        end
      end

      path = f.service.manual_command
      expect(path).to eq("#{HOMEBREW_PREFIX}/opt/formula_name/bin/beanstalkd")
    end
  end

  describe "#to_plist" do
    it "returns valid plist" do
      f = stub_formula do
        service do
          run [opt_bin/"beanstalkd", "test"]
          run_type :immediate
          environment_variables PATH: std_service_path_env, FOO: "BAR", ETC_DIR: etc/"beanstalkd"
          error_log_path var/"log/beanstalkd.error.log"
          log_path var/"log/beanstalkd.log"
          input_path var/"in/beanstalkd"
          require_root true
          root_dir var
          working_dir var
          keep_alive true
          launch_only_once true
          process_type :interactive
          restart_delay 30
          interval 5
          macos_legacy_timers true
        end
      end

      plist = f.service.to_plist
      plist_expect = <<~EOS
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
        \t<key>EnvironmentVariables</key>
        \t<dict>
        \t\t<key>ETC_DIR</key>
        \t\t<string>#{HOMEBREW_PREFIX}/etc/beanstalkd</string>
        \t\t<key>FOO</key>
        \t\t<string>BAR</string>
        \t\t<key>PATH</key>
        \t\t<string>#{HOMEBREW_PREFIX}/bin:#{HOMEBREW_PREFIX}/sbin:/usr/bin:/bin:/usr/sbin:/sbin</string>
        \t</dict>
        \t<key>KeepAlive</key>
        \t<true/>
        \t<key>Label</key>
        \t<string>homebrew.mxcl.formula_name</string>
        \t<key>LaunchOnlyOnce</key>
        \t<true/>
        \t<key>LegacyTimers</key>
        \t<true/>
        \t<key>LimitLoadToSessionType</key>
        \t<array>
        \t\t<string>Aqua</string>
        \t\t<string>Background</string>
        \t\t<string>LoginWindow</string>
        \t\t<string>StandardIO</string>
        \t\t<string>System</string>
        \t</array>
        \t<key>ProcessType</key>
        \t<string>Interactive</string>
        \t<key>ProgramArguments</key>
        \t<array>
        \t\t<string>#{HOMEBREW_PREFIX}/opt/formula_name/bin/beanstalkd</string>
        \t\t<string>test</string>
        \t</array>
        \t<key>RootDirectory</key>
        \t<string>#{HOMEBREW_PREFIX}/var</string>
        \t<key>RunAtLoad</key>
        \t<true/>
        \t<key>StandardErrorPath</key>
        \t<string>#{HOMEBREW_PREFIX}/var/log/beanstalkd.error.log</string>
        \t<key>StandardInPath</key>
        \t<string>#{HOMEBREW_PREFIX}/var/in/beanstalkd</string>
        \t<key>StandardOutPath</key>
        \t<string>#{HOMEBREW_PREFIX}/var/log/beanstalkd.log</string>
        \t<key>TimeOut</key>
        \t<integer>30</integer>
        \t<key>WorkingDirectory</key>
        \t<string>#{HOMEBREW_PREFIX}/var</string>
        </dict>
        </plist>
      EOS
      expect(plist).to eq(plist_expect)
    end

    it "returns valid plist with socket" do
      plist_expect = <<~EOS
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
        \t<key>Label</key>
        \t<string>homebrew.mxcl.formula_name</string>
        \t<key>LimitLoadToSessionType</key>
        \t<array>
        \t\t<string>Aqua</string>
        \t\t<string>Background</string>
        \t\t<string>LoginWindow</string>
        \t\t<string>StandardIO</string>
        \t\t<string>System</string>
        \t</array>
        \t<key>ProgramArguments</key>
        \t<array>
        \t\t<string>#{HOMEBREW_PREFIX}/opt/formula_name/bin/beanstalkd</string>
        \t</array>
        \t<key>RunAtLoad</key>
        \t<true/>
        \t<key>Sockets</key>
        \t<dict>
        \t\t<key>listeners</key>
        \t\t<dict>
        \t\t\t<key>SockNodeName</key>
        \t\t\t<string>127.0.0.1</string>
        \t\t\t<key>SockProtocol</key>
        \t\t\t<string>TCP</string>
        \t\t\t<key>SockServiceName</key>
        \t\t\t<string>80</string>
        \t\t</dict>
        \t</dict>
        </dict>
        </plist>
      EOS

      [
        stub_formula_with_service_sockets("tcp://127.0.0.1:80"),
        stub_formula_with_service_sockets({ listeners: "tcp://127.0.0.1:80" }),
      ].each do |f|
        plist = f.service.to_plist
        expect(plist).to eq(plist_expect)
      end
    end

    it "returns valid plist with multiple sockets" do
      f = stub_formula do
        service do
          run [opt_bin/"beanstalkd", "test"]
          sockets socket: "tcp://0.0.0.0:80", socket_tls: "tcp://0.0.0.0:443"
        end
      end

      plist = f.service.to_plist
      plist_expect = <<~EOS
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
        \t<key>Label</key>
        \t<string>homebrew.mxcl.formula_name</string>
        \t<key>LimitLoadToSessionType</key>
        \t<array>
        \t\t<string>Aqua</string>
        \t\t<string>Background</string>
        \t\t<string>LoginWindow</string>
        \t\t<string>StandardIO</string>
        \t\t<string>System</string>
        \t</array>
        \t<key>ProgramArguments</key>
        \t<array>
        \t\t<string>#{HOMEBREW_PREFIX}/opt/formula_name/bin/beanstalkd</string>
        \t\t<string>test</string>
        \t</array>
        \t<key>RunAtLoad</key>
        \t<true/>
        \t<key>Sockets</key>
        \t<dict>
        \t\t<key>socket</key>
        \t\t<dict>
        \t\t\t<key>SockNodeName</key>
        \t\t\t<string>0.0.0.0</string>
        \t\t\t<key>SockProtocol</key>
        \t\t\t<string>TCP</string>
        \t\t\t<key>SockServiceName</key>
        \t\t\t<string>80</string>
        \t\t</dict>
        \t\t<key>socket_tls</key>
        \t\t<dict>
        \t\t\t<key>SockNodeName</key>
        \t\t\t<string>0.0.0.0</string>
        \t\t\t<key>SockProtocol</key>
        \t\t\t<string>TCP</string>
        \t\t\t<key>SockServiceName</key>
        \t\t\t<string>443</string>
        \t\t</dict>
        \t</dict>
        </dict>
        </plist>
      EOS
      expect(plist).to eq(plist_expect)
    end

    it "returns valid partial plist" do
      f = stub_formula do
        service do
          run opt_bin/"beanstalkd"
          run_type :immediate
        end
      end

      plist = f.service.to_plist
      plist_expect = <<~EOS
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
        \t<key>Label</key>
        \t<string>homebrew.mxcl.formula_name</string>
        \t<key>LimitLoadToSessionType</key>
        \t<array>
        \t\t<string>Aqua</string>
        \t\t<string>Background</string>
        \t\t<string>LoginWindow</string>
        \t\t<string>StandardIO</string>
        \t\t<string>System</string>
        \t</array>
        \t<key>ProgramArguments</key>
        \t<array>
        \t\t<string>#{HOMEBREW_PREFIX}/opt/formula_name/bin/beanstalkd</string>
        \t</array>
        \t<key>RunAtLoad</key>
        \t<true/>
        </dict>
        </plist>
      EOS
      expect(plist).to eq(plist_expect)
    end

    it "returns valid partial plist with run_at_load being false" do
      f = stub_formula do
        service do
          run opt_bin/"beanstalkd"
          run_type :immediate
          run_at_load false
        end
      end

      plist = f.service.to_plist
      plist_expect = <<~EOS
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
        \t<key>Label</key>
        \t<string>homebrew.mxcl.formula_name</string>
        \t<key>LimitLoadToSessionType</key>
        \t<array>
        \t\t<string>Aqua</string>
        \t\t<string>Background</string>
        \t\t<string>LoginWindow</string>
        \t\t<string>StandardIO</string>
        \t\t<string>System</string>
        \t</array>
        \t<key>ProgramArguments</key>
        \t<array>
        \t\t<string>#{HOMEBREW_PREFIX}/opt/formula_name/bin/beanstalkd</string>
        \t</array>
        \t<key>RunAtLoad</key>
        \t<false/>
        </dict>
        </plist>
      EOS
      expect(plist).to eq(plist_expect)
    end

    it "returns valid interval plist" do
      f = stub_formula do
        service do
          run opt_bin/"beanstalkd"
          run_type :interval
          interval 5
        end
      end

      plist = f.service.to_plist
      plist_expect = <<~EOS
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
        \t<key>Label</key>
        \t<string>homebrew.mxcl.formula_name</string>
        \t<key>LimitLoadToSessionType</key>
        \t<array>
        \t\t<string>Aqua</string>
        \t\t<string>Background</string>
        \t\t<string>LoginWindow</string>
        \t\t<string>StandardIO</string>
        \t\t<string>System</string>
        \t</array>
        \t<key>ProgramArguments</key>
        \t<array>
        \t\t<string>#{HOMEBREW_PREFIX}/opt/formula_name/bin/beanstalkd</string>
        \t</array>
        \t<key>RunAtLoad</key>
        \t<true/>
        \t<key>StartInterval</key>
        \t<integer>5</integer>
        </dict>
        </plist>
      EOS
      expect(plist).to eq(plist_expect)
    end

    it "returns valid cron plist" do
      f = stub_formula do
        service do
          run opt_bin/"beanstalkd"
          run_type :cron
          cron "@daily"
        end
      end

      plist = f.service.to_plist
      plist_expect = <<~EOS
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
        \t<key>Label</key>
        \t<string>homebrew.mxcl.formula_name</string>
        \t<key>LimitLoadToSessionType</key>
        \t<array>
        \t\t<string>Aqua</string>
        \t\t<string>Background</string>
        \t\t<string>LoginWindow</string>
        \t\t<string>StandardIO</string>
        \t\t<string>System</string>
        \t</array>
        \t<key>ProgramArguments</key>
        \t<array>
        \t\t<string>#{HOMEBREW_PREFIX}/opt/formula_name/bin/beanstalkd</string>
        \t</array>
        \t<key>RunAtLoad</key>
        \t<true/>
        \t<key>StartCalendarInterval</key>
        \t<dict>
        \t\t<key>Hour</key>
        \t\t<integer>0</integer>
        \t\t<key>Minute</key>
        \t\t<integer>0</integer>
        \t</dict>
        </dict>
        </plist>
      EOS
      expect(plist).to eq(plist_expect)
    end

    it "returns valid keepalive-exit plist" do
      f = stub_formula do
        service do
          run opt_bin/"beanstalkd"
          keep_alive successful_exit: false
        end
      end

      plist = f.service.to_plist
      plist_expect = <<~EOS
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
        \t<key>KeepAlive</key>
        \t<dict>
        \t\t<key>SuccessfulExit</key>
        \t\t<false/>
        \t</dict>
        \t<key>Label</key>
        \t<string>homebrew.mxcl.formula_name</string>
        \t<key>LimitLoadToSessionType</key>
        \t<array>
        \t\t<string>Aqua</string>
        \t\t<string>Background</string>
        \t\t<string>LoginWindow</string>
        \t\t<string>StandardIO</string>
        \t\t<string>System</string>
        \t</array>
        \t<key>ProgramArguments</key>
        \t<array>
        \t\t<string>#{HOMEBREW_PREFIX}/opt/formula_name/bin/beanstalkd</string>
        \t</array>
        \t<key>RunAtLoad</key>
        \t<true/>
        </dict>
        </plist>
      EOS
      expect(plist).to eq(plist_expect)
    end

    it "returns valid keepalive-crashed plist" do
      f = stub_formula do
        service do
          run opt_bin/"beanstalkd"
          keep_alive crashed: true
        end
      end

      plist = f.service.to_plist
      plist_expect = <<~EOS
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
        \t<key>KeepAlive</key>
        \t<dict>
        \t\t<key>Crashed</key>
        \t\t<true/>
        \t</dict>
        \t<key>Label</key>
        \t<string>homebrew.mxcl.formula_name</string>
        \t<key>LimitLoadToSessionType</key>
        \t<array>
        \t\t<string>Aqua</string>
        \t\t<string>Background</string>
        \t\t<string>LoginWindow</string>
        \t\t<string>StandardIO</string>
        \t\t<string>System</string>
        \t</array>
        \t<key>ProgramArguments</key>
        \t<array>
        \t\t<string>#{HOMEBREW_PREFIX}/opt/formula_name/bin/beanstalkd</string>
        \t</array>
        \t<key>RunAtLoad</key>
        \t<true/>
        </dict>
        </plist>
      EOS
      expect(plist).to eq(plist_expect)
    end

    it "returns valid keepalive-path plist" do
      f = stub_formula do
        service do
          run opt_bin/"beanstalkd"
          keep_alive path: opt_pkgshare/"test-path"
        end
      end

      plist = f.service.to_plist
      plist_expect = <<~EOS
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
        \t<key>KeepAlive</key>
        \t<dict>
        \t\t<key>PathState</key>
        \t\t<string>#{HOMEBREW_PREFIX}/opt/formula_name/share/formula_name/test-path</string>
        \t</dict>
        \t<key>Label</key>
        \t<string>homebrew.mxcl.formula_name</string>
        \t<key>LimitLoadToSessionType</key>
        \t<array>
        \t\t<string>Aqua</string>
        \t\t<string>Background</string>
        \t\t<string>LoginWindow</string>
        \t\t<string>StandardIO</string>
        \t\t<string>System</string>
        \t</array>
        \t<key>ProgramArguments</key>
        \t<array>
        \t\t<string>#{HOMEBREW_PREFIX}/opt/formula_name/bin/beanstalkd</string>
        \t</array>
        \t<key>RunAtLoad</key>
        \t<true/>
        </dict>
        </plist>
      EOS
      expect(plist).to eq(plist_expect)
    end

    it "expands paths" do
      f = stub_formula do
        service do
          run [opt_sbin/"sleepwatcher", "-V", "-s", "~/.sleep", "-w", "~/.wakeup"]
          working_dir "~"
        end
      end

      plist = f.service.to_plist
      plist_expect = <<~EOS
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
        \t<key>Label</key>
        \t<string>homebrew.mxcl.formula_name</string>
        \t<key>LimitLoadToSessionType</key>
        \t<array>
        \t\t<string>Aqua</string>
        \t\t<string>Background</string>
        \t\t<string>LoginWindow</string>
        \t\t<string>StandardIO</string>
        \t\t<string>System</string>
        \t</array>
        \t<key>ProgramArguments</key>
        \t<array>
        \t\t<string>#{HOMEBREW_PREFIX}/opt/formula_name/sbin/sleepwatcher</string>
        \t\t<string>-V</string>
        \t\t<string>-s</string>
        \t\t<string>#{Dir.home}/.sleep</string>
        \t\t<string>-w</string>
        \t\t<string>#{Dir.home}/.wakeup</string>
        \t</array>
        \t<key>RunAtLoad</key>
        \t<true/>
        \t<key>WorkingDirectory</key>
        \t<string>#{Dir.home}</string>
        </dict>
        </plist>
      EOS
      expect(plist).to eq(plist_expect)
    end
  end

  describe "#to_systemd_unit" do
    it "returns valid unit" do
      f = stub_formula do
        service do
          run [opt_bin/"beanstalkd", "test"]
          run_type :immediate
          environment_variables PATH: std_service_path_env, FOO: "BAR"
          error_log_path var/"log/beanstalkd.error.log"
          log_path var/"log/beanstalkd.log"
          input_path var/"in/beanstalkd"
          require_root true
          root_dir var
          working_dir var
          keep_alive true
          process_type :interactive
          restart_delay 30
          macos_legacy_timers true
        end
      end

      unit = f.service.to_systemd_unit
      std_path = "#{HOMEBREW_PREFIX}/bin:#{HOMEBREW_PREFIX}/sbin:/usr/bin:/bin:/usr/sbin:/sbin"
      unit_expect = <<~SYSTEMD
        [Unit]
        Description=Homebrew generated unit for formula_name

        [Install]
        WantedBy=default.target

        [Service]
        Type=simple
        ExecStart="#{HOMEBREW_PREFIX}/opt/#{name}/bin/beanstalkd" "test"
        Restart=always
        RestartSec=30
        WorkingDirectory=#{HOMEBREW_PREFIX}/var
        RootDirectory=#{HOMEBREW_PREFIX}/var
        StandardInput=file:#{HOMEBREW_PREFIX}/var/in/beanstalkd
        StandardOutput=append:#{HOMEBREW_PREFIX}/var/log/beanstalkd.log
        StandardError=append:#{HOMEBREW_PREFIX}/var/log/beanstalkd.error.log
        Environment="PATH=#{std_path}"
        Environment="FOO=BAR"
      SYSTEMD
      expect(unit).to eq(unit_expect)
    end

    it "returns valid partial oneshot unit" do
      f = stub_formula do
        service do
          run opt_bin/"beanstalkd"
          run_type :immediate
          launch_only_once true
        end
      end

      unit = f.service.to_systemd_unit
      unit_expect = <<~SYSTEMD
        [Unit]
        Description=Homebrew generated unit for formula_name

        [Install]
        WantedBy=default.target

        [Service]
        Type=oneshot
        ExecStart="#{HOMEBREW_PREFIX}/opt/#{name}/bin/beanstalkd"
      SYSTEMD
      expect(unit).to eq(unit_expect)
    end

    it "expands paths" do
      f = stub_formula do
        service do
          run opt_bin/"beanstalkd"
          working_dir "~"
        end
      end

      unit = f.service.to_systemd_unit
      unit_expect = <<~SYSTEMD
        [Unit]
        Description=Homebrew generated unit for formula_name

        [Install]
        WantedBy=default.target

        [Service]
        Type=simple
        ExecStart="#{HOMEBREW_PREFIX}/opt/#{name}/bin/beanstalkd"
        WorkingDirectory=#{Dir.home}
      SYSTEMD
      expect(unit).to eq(unit_expect)
    end
  end

  describe "#to_systemd_timer" do
    it "returns valid timer" do
      f = stub_formula do
        service do
          run [opt_bin/"beanstalkd", "test"]
          run_type :interval
          interval 5
        end
      end

      unit = f.service.to_systemd_timer
      unit_expect = <<~SYSTEMD
        [Unit]
        Description=Homebrew generated timer for formula_name

        [Install]
        WantedBy=timers.target

        [Timer]
        Unit=homebrew.formula_name
        OnUnitActiveSec=5
      SYSTEMD
      expect(unit).to eq(unit_expect)
    end

    it "returns valid partial timer" do
      f = stub_formula do
        service do
          run opt_bin/"beanstalkd"
          run_type :immediate
        end
      end

      unit = f.service.to_systemd_timer
      unit_expect = <<~SYSTEMD
        [Unit]
        Description=Homebrew generated timer for formula_name

        [Install]
        WantedBy=timers.target

        [Timer]
        Unit=homebrew.formula_name

      SYSTEMD
      expect(unit).to eq(unit_expect)
    end

    it "throws on incomplete cron" do
      f = stub_formula do
        service do
          run opt_bin/"beanstalkd"
          run_type :cron
          cron "1 2 3 4"
        end
      end

      expect do
        f.service.to_systemd_timer
      end.to raise_error TypeError, "Service#parse_cron expects a valid cron syntax"
    end

    it "returns valid cron timers" do
      styles = {
        "@hourly":   "*-*-*-* *:00:00",
        "@daily":    "*-*-*-* 00:00:00",
        "@weekly":   "0-*-*-* 00:00:00",
        "@monthly":  "*-*-*-1 00:00:00",
        "@yearly":   "*-*-1-1 00:00:00",
        "@annually": "*-*-1-1 00:00:00",
        "5 5 5 5 5": "5-*-5-5 05:05:00",
      }

      styles.each do |cron, calendar|
        f = stub_formula do
          service do
            run opt_bin/"beanstalkd"
            run_type :cron
            cron cron.to_s
          end
        end

        unit = f.service.to_systemd_timer
        unit_expect = <<~SYSTEMD
          [Unit]
          Description=Homebrew generated timer for formula_name

          [Install]
          WantedBy=timers.target

          [Timer]
          Unit=homebrew.formula_name
          Persistent=true
          OnCalendar=#{calendar}
        SYSTEMD
        expect(unit).to eq(unit_expect)
      end
    end
  end

  describe "#timed?" do
    it "returns false for immediate" do
      f = stub_formula do
        service do
          run [opt_bin/"beanstalkd", "test"]
          run_type :immediate
        end
      end

      expect(f.service.timed?).to be(false)
    end

    it "returns true for interval" do
      f = stub_formula do
        service do
          run [opt_bin/"beanstalkd", "test"]
          run_type :interval
        end
      end

      expect(f.service.timed?).to be(true)
    end
  end

  describe "#keep_alive?" do
    it "returns true when keep_alive set to hash" do
      f = stub_formula do
        service do
          run [opt_bin/"beanstalkd", "test"]
          keep_alive crashed: true
        end
      end

      expect(f.service.keep_alive?).to be(true)
    end

    it "returns true when keep_alive set to true" do
      f = stub_formula do
        service do
          run [opt_bin/"beanstalkd", "test"]
          keep_alive true
        end
      end

      expect(f.service.keep_alive?).to be(true)
    end

    it "returns false when keep_alive not set" do
      f = stub_formula do
        service do
          run [opt_bin/"beanstalkd", "test"]
        end
      end

      expect(f.service.keep_alive?).to be(false)
    end

    it "returns false when keep_alive set to false" do
      f = stub_formula do
        service do
          run [opt_bin/"beanstalkd", "test"]
          keep_alive false
        end
      end

      expect(f.service.keep_alive?).to be(false)
    end
  end

  describe "#command" do
    it "returns @run data" do
      f = stub_formula do
        service do
          run [opt_bin/"beanstalkd", "test"]
          run_type :immediate
        end
      end

      command = f.service.command
      expect(command).to eq(["#{HOMEBREW_PREFIX}/opt/#{name}/bin/beanstalkd", "test"])
    end

    it "returns @run data on Linux", :needs_linux do
      f = stub_formula do
        service do
          run linux: [opt_bin/"beanstalkd", "test"]
          run_type :immediate
        end
      end

      command = f.service.command
      expect(command).to eq(["#{HOMEBREW_PREFIX}/opt/#{name}/bin/beanstalkd", "test"])
    end

    it "returns nil on Linux", :needs_linux do
      f = stub_formula do
        service do
          run macos: [opt_bin/"beanstalkd", "test"]
          run_type :immediate
        end
      end

      command = f.service.command
      expect(command).to be_nil
    end

    it "returns @run data on macOS", :needs_macos do
      f = stub_formula do
        service do
          run macos: [opt_bin/"beanstalkd", "test"]
          run_type :immediate
        end
      end

      command = f.service.command
      expect(command).to eq(["#{HOMEBREW_PREFIX}/opt/#{name}/bin/beanstalkd", "test"])
    end

    it "returns nil on macOS", :needs_macos do
      f = stub_formula do
        service do
          run linux: [opt_bin/"beanstalkd", "test"]
          run_type :immediate
        end
      end

      command = f.service.command
      expect(command).to be_nil
    end

    it "returns appropriate @run data on Linux", :needs_linux do
      f = stub_formula do
        service do
          run macos: [opt_bin/"beanstalkd", "test", "macos"], linux: [opt_bin/"beanstalkd", "test", "linux"]
          run_type :immediate
        end
      end

      command = f.service.command
      expect(command).to eq(["#{HOMEBREW_PREFIX}/opt/#{name}/bin/beanstalkd", "test", "linux"])
    end

    it "returns appropriate @run data on macOS", :needs_macos do
      f = stub_formula do
        service do
          run macos: [opt_bin/"beanstalkd", "test", "macos"], linux: [opt_bin/"beanstalkd", "test", "linux"]
          run_type :immediate
        end
      end

      command = f.service.command
      expect(command).to eq(["#{HOMEBREW_PREFIX}/opt/#{name}/bin/beanstalkd", "test", "macos"])
    end
  end

  describe "#to_hash" do
    let(:serialized_hash) do
      {
        environment_variables: {
          PATH: "$HOMEBREW_PREFIX/bin:$HOMEBREW_PREFIX/sbin:/usr/bin:/bin:/usr/sbin:/sbin",
        },
        run:                   [Pathname("$HOMEBREW_PREFIX/opt/formula_name/bin/beanstalkd"), "test"],
        run_type:              :immediate,
        working_dir:           "/$HOME",
        cron:                  "0 0 * * 0",
        sockets:               "tcp://0.0.0.0:80",
      }
    end

    # NOTE: The calls to `Formula.generating_hash!` and `Formula.generated_hash!`
    #       are not idempotent so they can only be used in one test.
    it "replaces local paths with placeholders" do
      f = stub_formula do
        service do
          run [opt_bin/"beanstalkd", "test"]
          environment_variables PATH: std_service_path_env
          working_dir Dir.home
          cron "@weekly"
          sockets "tcp://0.0.0.0:80"
        end
      end

      Formula.generating_hash!
      expect(f.service.to_hash).to eq(serialized_hash)
      Formula.generated_hash!
    end
  end

  describe ".from_hash" do
    let(:serialized_hash) do
      {
        "name"                  => {
          "linux" => "custom.systemd.name",
          "macos" => "custom.launchd.name",
        },
        "environment_variables" => {
          "PATH" => "$HOMEBREW_PREFIX/bin:$HOMEBREW_PREFIX/sbin:/usr/bin:/bin:/usr/sbin:/sbin",
        },
        "run"                   => ["$HOMEBREW_PREFIX/opt/formula_name/bin/beanstalkd", "test"],
        "run_type"              => "immediate",
        "working_dir"           => HOMEBREW_HOME_PLACEHOLDER,
        "keep_alive"            => { "successful_exit" => false },
      }
    end

    let(:deserialized_hash) do
      {
        name:                  {
          linux: "custom.systemd.name",
          macos: "custom.launchd.name",
        },
        environment_variables: {
          PATH: "#{HOMEBREW_PREFIX}/bin:#{HOMEBREW_PREFIX}/sbin:/usr/bin:/bin:/usr/sbin:/sbin",
        },
        run:                   ["#{HOMEBREW_PREFIX}/opt/formula_name/bin/beanstalkd", "test"],
        run_type:              :immediate,
        working_dir:           Dir.home,
        keep_alive:            { successful_exit: false },
      }
    end

    it "replaces placeholders with local paths" do
      expect(described_class.from_hash(serialized_hash)).to eq(deserialized_hash)
    end

    describe "run command" do
      it "handles String argument correctly" do
        expect(described_class.from_hash({
          "run" => "$HOMEBREW_PREFIX/opt/formula_name/bin/beanstalkd",
        })).to eq({
          run: "#{HOMEBREW_PREFIX}/opt/formula_name/bin/beanstalkd",
        })
      end

      it "handles Array argument correctly" do
        expect(described_class.from_hash({
          "run" => ["$HOMEBREW_PREFIX/opt/formula_name/bin/beanstalkd", "--option"],
        })).to eq({
          run: ["#{HOMEBREW_PREFIX}/opt/formula_name/bin/beanstalkd", "--option"],
        })
      end

      it "handles Hash argument correctly" do
        expect(described_class.from_hash({
          "run" => {
            "linux" => "$HOMEBREW_PREFIX/opt/formula_name/bin/beanstalkd",
            "macos" => ["$HOMEBREW_PREFIX/opt/formula_name/bin/beanstalkd", "--option"],
          },
        })).to eq({
          run: {
            linux: "#{HOMEBREW_PREFIX}/opt/formula_name/bin/beanstalkd",
            macos: ["#{HOMEBREW_PREFIX}/opt/formula_name/bin/beanstalkd", "--option"],
          },
        })
      end
    end
  end
end
