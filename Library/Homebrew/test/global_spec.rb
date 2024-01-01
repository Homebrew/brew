# frozen_string_literal: true

describe "brew", :integration_test do
  it "does not invoke `require \"formula\"` at startup" do
    expect { brew "verify-formula-undefined" }
      .to not_to_output.to_stdout
      .and not_to_output.to_stderr
      .and be_a_success
  end

  it "does not require i18n" do
    # This is a transitive dependency of activesupport, but we don't use it.
    expect { I18n }.to raise_error(NameError)
  end
end
