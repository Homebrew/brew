# typed: true
# frozen_string_literal: true

require "socket"
require "formula_free_port"

RSpec.describe Homebrew::FreePort do
  subject(:instance) { Object.new.extend(described_class) }

  describe "#free_port" do
    it "returns a free TCP/IP port" do
      # IANA recommends:
      # - User ports:   1024–49151
      # - Dynamic ports: 49152–65535
      # For this test we accept any free port in the full 1024–65535 range.
      # http://www.iana.org/assignments/port-numbers
      min_port = 1024
      max_port = 65535
      port = instance.free_port

      expect(port).to be_between(min_port, max_port)
      expect { TCPServer.new(port).close }.not_to raise_error
    end
  end
end
