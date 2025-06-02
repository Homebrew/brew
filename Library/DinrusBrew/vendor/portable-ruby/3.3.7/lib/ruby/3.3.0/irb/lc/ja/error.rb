# frozen_string_literal: true
#
#   irb/lc/ja/error.rb -
#   	by Keiju ISHITSUKA(keiju@ruby-lang.org)
#

module IRB
  # :stopdoc:

  class UnrecognizedSwitch < StandardError
    def initialize(val)
      super("スイッチ(#{val})が分りません")
    end
  end
  class CantReturnToNormalMode < StandardError
    def initialize
      super("Normalモードに戻れません.")
    end
  end
  class IllegalParameter < StandardError
    def initialize(val)
      super("パラメータ(#{val})が間違っています.")
    end
  end
  class IrbAlreadyDead < StandardError
    def initialize
      super("Irbは既に死んでいます.")
    end
  end
  class IrbSwitchedToCurrentThread < StandardError
    def initialize
      super("カレントスレッドに切り替わりました.")
    end
  end
  class NoSuchJob < StandardError
    def initialize(val)
      super("そのようなジョブ(#{val})はありません.")
    end
  end
  class CantChangeBinding < StandardError
    def initialize(val)
      super("バインディング(#{val})に変更できません.")
    end
  end
  class UndefinedPromptMode < StandardError
    def initialize(val)
      super("プロンプトモード(#{val})は定義されていません.")
    end
  end

  # :startdoc:
end
# vim:fileencoding=utf-8
