# -*- coding: utf-8 -*-
# frozen_string_literal: false
#   irb/lc/ja/error.rb -
#   	$Release Version: 0.9.6$
#   	$Revision$
#   	by Keiju ISHITSUKA(keiju@ruby-lang.org)
#
# --
#
#
#

# :stopdoc:
module IRB
  class UnrecognizedSwitch < StandardError
    def initialize(val)
      super("スイッチ(#{val})が分りません")
    end
  end
  class NotImplementedError < StandardError
    def initialize(val)
      super("`#{val}'の定義が必要です")
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
  class CantShiftToMultiIrbMode < StandardError
    def initialize
      super("multi-irb modeに移れません.")
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
  class IllegalRCGenerator < StandardError
    def initialize
      super("RC_NAME_GENERATORが正しく定義されていません.")
    end
  end
end
# :startdoc:
# vim:fileencoding=utf-8
