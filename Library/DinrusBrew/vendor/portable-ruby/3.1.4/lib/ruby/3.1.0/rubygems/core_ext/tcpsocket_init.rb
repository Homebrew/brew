require "socket"

module CoreExtensions
  module TCPSocketExt
    def self.prepended(base)
      base.prepend Initializer
    end

    module Initializer
      CONNECTION_TIMEOUT = 5
      IPV4_DELAY_SECONDS = 0.1

      def initialize(host, serv, *rest)
        mutex = Thread::Mutex.new
        addrs = []
        threads = []
        cond_var = Thread::ConditionVariable.new

        Addrinfo.foreach(host, serv, nil, :STREAM) do |addr|
          Thread.report_on_exception = false if defined? Thread.report_on_exception = ()

          threads << Thread.new(addr) do
            # give head start to ipv6 addresses
            sleep IPV4_DELAY_SECONDS if addr.ipv4?

            # raises Errno::ECONNREFUSED when ip:port is unreachable
            Socket.tcp(addr.ip_address, serv, connect_timeout: CONNECTION_TIMEOUT).close
            mutex.synchronize do
              addrs << addr.ip_address
              cond_var.signal
            end
          end
        end

        mutex.synchronize do
          timeout_time = CONNECTION_TIMEOUT + Time.now.to_f
          while addrs.empty? && (remaining_time = timeout_time - Time.now.to_f) > 0
            cond_var.wait(mutex, remaining_time)
          end

          host = addrs.shift unless addrs.empty?
        end

        threads.each {|t| t.kill.join if t.alive? }

        super(host, serv, *rest)
      end
    end
  end
end

TCPSocket.prepend CoreExtensions::TCPSocketExt
