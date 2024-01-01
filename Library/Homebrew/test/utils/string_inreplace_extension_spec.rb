# frozen_string_literal: true

require "utils/string_inreplace_extension"

describe StringInreplaceExtension do
  subject(:string_extension) { described_class.new(string.dup) }

  describe "#change_make_var!" do
    context "with a flag" do
      context "with spaces" do
        let(:string) do
          <<~EOS
            OTHER=def
            FLAG = abc
            FLAG2=abc
          EOS
        end

        it "is successfully replaced" do
          string_extension.change_make_var! "FLAG", "def"
          expect(string_extension.inreplace_string).to eq <<~EOS
            OTHER=def
            FLAG=def
            FLAG2=abc
          EOS
        end

        it "is successfully appended" do
          string_extension.change_make_var! "FLAG", "\\1 def"
          expect(string_extension.inreplace_string).to eq <<~EOS
            OTHER=def
            FLAG=abc def
            FLAG2=abc
          EOS
        end
      end

      context "with tabs" do
        let(:string) do
          <<~EOS
            CFLAGS\t=\t-Wall -O2
            LDFLAGS\t=\t-lcrypto -lssl
          EOS
        end

        it "is successfully replaced" do
          string_extension.change_make_var! "CFLAGS", "-O3"
          expect(string_extension.inreplace_string).to eq <<~EOS
            CFLAGS=-O3
            LDFLAGS\t=\t-lcrypto -lssl
          EOS
        end
      end

      context "with newlines" do
        let(:string) do
          <<~'EOS'
            CFLAGS = -Wall -O2 \
                     -DSOME_VAR=1
            LDFLAGS = -lcrypto -lssl
          EOS
        end

        it "is successfully replaced" do
          string_extension.change_make_var! "CFLAGS", "-O3"
          expect(string_extension.inreplace_string).to eq <<~EOS
            CFLAGS=-O3
            LDFLAGS = -lcrypto -lssl
          EOS
        end
      end
    end

    context "with an empty flag between other flags" do
      let(:string) do
        <<~EOS
          OTHER=def
          FLAG =
          FLAG2=abc
        EOS
      end

      it "is successfully replaced" do
        string_extension.change_make_var! "FLAG", "def"
        expect(string_extension.inreplace_string).to eq <<~EOS
          OTHER=def
          FLAG=def
          FLAG2=abc
        EOS
      end
    end

    context "with an empty flag" do
      let(:string) do
        <<~EOS
          FLAG =
          mv file_a file_b
        EOS
      end

      it "is successfully replaced" do
        string_extension.change_make_var! "FLAG", "def"
        expect(string_extension.inreplace_string).to eq <<~EOS
          FLAG=def
          mv file_a file_b
        EOS
      end
    end

    context "with shell-style variable" do
      let(:string) do
        <<~EOS
          OTHER=def
          FLAG=abc
          FLAG2=abc
        EOS
      end

      it "is successfully replaced" do
        string_extension.change_make_var! "FLAG", "def"
        expect(string_extension.inreplace_string).to eq <<~EOS
          OTHER=def
          FLAG=def
          FLAG2=abc
        EOS
      end
    end
  end

  describe "#remove_make_var!" do
    context "with a flag" do
      context "with spaces" do
        let(:string) do
          <<~EOS
            OTHER=def
            FLAG = abc
            FLAG2 = def
          EOS
        end

        it "is successfully removed" do
          string_extension.remove_make_var! "FLAG"
          expect(string_extension.inreplace_string).to eq <<~EOS
            OTHER=def
            FLAG2 = def
          EOS
        end
      end

      context "with tabs" do
        let(:string) do
          <<~EOS
            CFLAGS\t=\t-Wall -O2
            LDFLAGS\t=\t-lcrypto -lssl
          EOS
        end

        it "is successfully removed" do
          string_extension.remove_make_var! "LDFLAGS"
          expect(string_extension.inreplace_string).to eq <<~EOS
            CFLAGS\t=\t-Wall -O2
          EOS
        end
      end

      context "with newlines" do
        let(:string) do
          <<~'EOS'
            CFLAGS = -Wall -O2 \
                     -DSOME_VAR=1
            LDFLAGS = -lcrypto -lssl
          EOS
        end

        it "is successfully removed" do
          string_extension.remove_make_var! "CFLAGS"
          expect(string_extension.inreplace_string).to eq <<~EOS
            LDFLAGS = -lcrypto -lssl
          EOS
        end
      end
    end

    context "with multiple flags" do
      let(:string) do
        <<~EOS
          OTHER=def
          FLAG = abc
          FLAG2 = def
          OTHER2=def
        EOS
      end

      specify "are be successfully removed" do
        string_extension.remove_make_var! ["FLAG", "FLAG2"]
        expect(string_extension.inreplace_string).to eq <<~EOS
          OTHER=def
          OTHER2=def
        EOS
      end
    end
  end

  describe "#get_make_var" do
    context "with spaces" do
      let(:string) do
        <<~EOS
          CFLAGS = -Wall -O2
          LDFLAGS = -lcrypto -lssl
        EOS
      end

      it "extracts the value for a given variable" do
        expect(string_extension.get_make_var("CFLAGS")).to eq("-Wall -O2")
      end
    end

    context "with tabs" do
      let(:string) do
        <<~EOS
          CFLAGS\t=\t-Wall -O2
          LDFLAGS\t=\t-lcrypto -lssl
        EOS
      end

      it "extracts the value for a given variable" do
        expect(string_extension.get_make_var("CFLAGS")).to eq("-Wall -O2")
      end
    end

    context "with newlines" do
      let(:string) do
        <<~'EOS'
          CFLAGS = -Wall -O2 \
                   -DSOME_VAR=1
          LDFLAGS = -lcrypto -lssl
        EOS
      end

      it "extracts the value for a given variable" do
        expect(string_extension.get_make_var("CFLAGS")).to match(/^-Wall -O2 \\\n +-DSOME_VAR=1$/)
      end
    end
  end

  describe "#sub!" do
    let(:string) { "foo" }

    it "replaces the first occurrence" do
      string_extension.sub!("o", "e")
      expect(string_extension.inreplace_string).to eq("feo")
    end

    it "adds an error to #errors when no replacement was made" do
      string_extension.sub! "not here", "test"
      expect(string_extension.errors).to eq(['expected replacement of "not here" with "test"'])
    end
  end

  describe "#gsub!" do
    let(:string) { "foo" }

    it "replaces all occurrences" do
      string_extension.gsub!("o", "e") # rubocop:disable Performance/StringReplacement
      expect(string_extension.inreplace_string).to eq("fee")
    end
  end
end
