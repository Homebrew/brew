# frozen_string_literal: true

require "socket"
require "formula_free_port"

RSpec.describe Homebrew::FreePort do
  include described_class

  describe "#free_port" do
    it "returns a free TCP/IP port" do
      # IANA suggests user port from 1024 to 49151
      # and dynamic port for 49152 to 65535
      # http://www.iana.org/assignments/port-numbers
      min_port = 1024
      max_port = 65535
      port = free_port

      expect(port).to be_between(min_port, max_port)
      expect { TCPServer.new(port).close }.not_to raise_error
    end
  end
end
