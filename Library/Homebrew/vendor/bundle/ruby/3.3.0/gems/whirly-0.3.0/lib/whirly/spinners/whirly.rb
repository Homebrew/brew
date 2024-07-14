require "json"

module Whirly
  module Spinners
    WHIRLY = {
      "random_dots"         => { "proc" => ->(){ [ 0x2800 + rand(256)].pack("U") }, "interval" => 100 },
      "mahjong"             => { "proc" => ->(){ [0x1F000 + rand(44)].pack("U") }, "interval" => 200 },
      "domino"              => { "proc" => ->(){ [0x1F030 + rand(50)].pack("U") }, "interval" => 200 },
      "vertical_domino"     => { "proc" => ->(){ [0x1F062 + rand(50)].pack("U") }, "interval" => 200 }
    }
    WHIRLY.merge! JSON.load(File.read(File.dirname(__FILE__) + "/../../../data/whirly-static-spinners.json"))

    WHIRLY.freeze
  end
end
