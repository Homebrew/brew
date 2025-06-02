module Reline::KeyActor
  EMACS_MAPPING = [
    #   0 ^@
    :em_set_mark,
    #   1 ^A
    :ed_move_to_beg,
    #   2 ^B
    :ed_prev_char,
    #   3 ^C
    :ed_ignore,
    #   4 ^D
    :em_delete,
    #   5 ^E
    :ed_move_to_end,
    #   6 ^F
    :ed_next_char,
    #   7 ^G
    :ed_unassigned,
    #   8 ^H
    :em_delete_prev_char,
    #   9 ^I
    :complete,
    #  10 ^J
    :ed_newline,
    #  11 ^K
    :ed_kill_line,
    #  12 ^L
    :ed_clear_screen,
    #  13 ^M
    :ed_newline,
    #  14 ^N
    :ed_next_history,
    #  15 ^O
    :ed_ignore,
    #  16 ^P
    :ed_prev_history,
    #  17 ^Q
    :ed_quoted_insert,
    #  18 ^R
    :vi_search_prev,
    #  19 ^S
    :vi_search_next,
    #  20 ^T
    :ed_transpose_chars,
    #  21 ^U
    :unix_line_discard,
    #  22 ^V
    :ed_quoted_insert,
    #  23 ^W
    :em_kill_region,
    #  24 ^X
    :ed_unassigned,
    #  25 ^Y
    :em_yank,
    #  26 ^Z
    :ed_ignore,
    #  27 ^[
    :ed_unassigned,
    #  28 ^\
    :ed_ignore,
    #  29 ^]
    :ed_ignore,
    #  30 ^^
    :ed_unassigned,
    #  31 ^_
    :undo,
    #  32 SPACE
    :ed_insert,
    #  33 !
    :ed_insert,
    #  34 "
    :ed_insert,
    #  35 #
    :ed_insert,
    #  36 $
    :ed_insert,
    #  37 %
    :ed_insert,
    #  38 &
    :ed_insert,
    #  39 '
    :ed_insert,
    #  40 (
    :ed_insert,
    #  41 )
    :ed_insert,
    #  42 *
    :ed_insert,
    #  43 +
    :ed_insert,
    #  44 ,
    :ed_insert,
    #  45 -
    :ed_insert,
    #  46 .
    :ed_insert,
    #  47 /
    :ed_insert,
    #  48 0
    :ed_digit,
    #  49 1
    :ed_digit,
    #  50 2
    :ed_digit,
    #  51 3
    :ed_digit,
    #  52 4
    :ed_digit,
    #  53 5
    :ed_digit,
    #  54 6
    :ed_digit,
    #  55 7
    :ed_digit,
    #  56 8
    :ed_digit,
    #  57 9
    :ed_digit,
    #  58 :
    :ed_insert,
    #  59 ;
    :ed_insert,
    #  60 <
    :ed_insert,
    #  61 =
    :ed_insert,
    #  62 >
    :ed_insert,
    #  63 ?
    :ed_insert,
    #  64 @
    :ed_insert,
    #  65 A
    :ed_insert,
    #  66 B
    :ed_insert,
    #  67 C
    :ed_insert,
    #  68 D
    :ed_insert,
    #  69 E
    :ed_insert,
    #  70 F
    :ed_insert,
    #  71 G
    :ed_insert,
    #  72 H
    :ed_insert,
    #  73 I
    :ed_insert,
    #  74 J
    :ed_insert,
    #  75 K
    :ed_insert,
    #  76 L
    :ed_insert,
    #  77 M
    :ed_insert,
    #  78 N
    :ed_insert,
    #  79 O
    :ed_insert,
    #  80 P
    :ed_insert,
    #  81 Q
    :ed_insert,
    #  82 R
    :ed_insert,
    #  83 S
    :ed_insert,
    #  84 T
    :ed_insert,
    #  85 U
    :ed_insert,
    #  86 V
    :ed_insert,
    #  87 W
    :ed_insert,
    #  88 X
    :ed_insert,
    #  89 Y
    :ed_insert,
    #  90 Z
    :ed_insert,
    #  91 [
    :ed_insert,
    #  92 \
    :ed_insert,
    #  93 ]
    :ed_insert,
    #  94 ^
    :ed_insert,
    #  95 _
    :ed_insert,
    #  96 `
    :ed_insert,
    #  97 a
    :ed_insert,
    #  98 b
    :ed_insert,
    #  99 c
    :ed_insert,
    # 100 d
    :ed_insert,
    # 101 e
    :ed_insert,
    # 102 f
    :ed_insert,
    # 103 g
    :ed_insert,
    # 104 h
    :ed_insert,
    # 105 i
    :ed_insert,
    # 106 j
    :ed_insert,
    # 107 k
    :ed_insert,
    # 108 l
    :ed_insert,
    # 109 m
    :ed_insert,
    # 110 n
    :ed_insert,
    # 111 o
    :ed_insert,
    # 112 p
    :ed_insert,
    # 113 q
    :ed_insert,
    # 114 r
    :ed_insert,
    # 115 s
    :ed_insert,
    # 116 t
    :ed_insert,
    # 117 u
    :ed_insert,
    # 118 v
    :ed_insert,
    # 119 w
    :ed_insert,
    # 120 x
    :ed_insert,
    # 121 y
    :ed_insert,
    # 122 z
    :ed_insert,
    # 123 {
    :ed_insert,
    # 124 |
    :ed_insert,
    # 125 }
    :ed_insert,
    # 126 ~
    :ed_insert,
    # 127 ^?
    :em_delete_prev_char,
    # 128 M-^@
    :ed_unassigned,
    # 129 M-^A
    :ed_unassigned,
    # 130 M-^B
    :ed_unassigned,
    # 131 M-^C
    :ed_unassigned,
    # 132 M-^D
    :ed_unassigned,
    # 133 M-^E
    :ed_unassigned,
    # 134 M-^F
    :ed_unassigned,
    # 135 M-^G
    :ed_unassigned,
    # 136 M-^H
    :ed_delete_prev_word,
    # 137 M-^I
    :ed_unassigned,
    # 138 M-^J
    :key_newline,
    # 139 M-^K
    :ed_unassigned,
    # 140 M-^L
    :ed_clear_screen,
    # 141 M-^M
    :key_newline,
    # 142 M-^N
    :ed_unassigned,
    # 143 M-^O
    :ed_unassigned,
    # 144 M-^P
    :ed_unassigned,
    # 145 M-^Q
    :ed_unassigned,
    # 146 M-^R
    :ed_unassigned,
    # 147 M-^S
    :ed_unassigned,
    # 148 M-^T
    :ed_unassigned,
    # 149 M-^U
    :ed_unassigned,
    # 150 M-^V
    :ed_unassigned,
    # 151 M-^W
    :ed_unassigned,
    # 152 M-^X
    :ed_unassigned,
    # 153 M-^Y
    :em_yank_pop,
    # 154 M-^Z
    :ed_unassigned,
    # 155 M-^[
    :ed_unassigned,
    # 156 M-^\
    :ed_unassigned,
    # 157 M-^]
    :ed_unassigned,
    # 158 M-^^
    :ed_unassigned,
    # 159 M-^_
    :redo,
    # 160 M-SPACE
    :em_set_mark,
    # 161 M-!
    :ed_unassigned,
    # 162 M-"
    :ed_unassigned,
    # 163 M-#
    :ed_unassigned,
    # 164 M-$
    :ed_unassigned,
    # 165 M-%
    :ed_unassigned,
    # 166 M-&
    :ed_unassigned,
    # 167 M-'
    :ed_unassigned,
    # 168 M-(
    :ed_unassigned,
    # 169 M-)
    :ed_unassigned,
    # 170 M-*
    :ed_unassigned,
    # 171 M-+
    :ed_unassigned,
    # 172 M-,
    :ed_unassigned,
    # 173 M--
    :ed_unassigned,
    # 174 M-.
    :ed_unassigned,
    # 175 M-/
    :ed_unassigned,
    # 176 M-0
    :ed_argument_digit,
    # 177 M-1
    :ed_argument_digit,
    # 178 M-2
    :ed_argument_digit,
    # 179 M-3
    :ed_argument_digit,
    # 180 M-4
    :ed_argument_digit,
    # 181 M-5
    :ed_argument_digit,
    # 182 M-6
    :ed_argument_digit,
    # 183 M-7
    :ed_argument_digit,
    # 184 M-8
    :ed_argument_digit,
    # 185 M-9
    :ed_argument_digit,
    # 186 M-:
    :ed_unassigned,
    # 187 M-;
    :ed_unassigned,
    # 188 M-<
    :ed_unassigned,
    # 189 M-=
    :ed_unassigned,
    # 190 M->
    :ed_unassigned,
    # 191 M-?
    :ed_unassigned,
    # 192 M-@
    :ed_unassigned,
    # 193 M-A
    :ed_unassigned,
    # 194 M-B
    :ed_prev_word,
    # 195 M-C
    :em_capitol_case,
    # 196 M-D
    :em_delete_next_word,
    # 197 M-E
    :ed_unassigned,
    # 198 M-F
    :em_next_word,
    # 199 M-G
    :ed_unassigned,
    # 200 M-H
    :ed_unassigned,
    # 201 M-I
    :ed_unassigned,
    # 202 M-J
    :ed_unassigned,
    # 203 M-K
    :ed_unassigned,
    # 204 M-L
    :em_lower_case,
    # 205 M-M
    :ed_unassigned,
    # 206 M-N
    :vi_search_next,
    # 207 M-O
    :ed_unassigned,
    # 208 M-P
    :vi_search_prev,
    # 209 M-Q
    :ed_unassigned,
    # 210 M-R
    :ed_unassigned,
    # 211 M-S
    :ed_unassigned,
    # 212 M-T
    :ed_unassigned,
    # 213 M-U
    :em_upper_case,
    # 214 M-V
    :ed_unassigned,
    # 215 M-W
    :ed_unassigned,
    # 216 M-X
    :ed_unassigned,
    # 217 M-Y
    :em_yank_pop,
    # 218 M-Z
    :ed_unassigned,
    # 219 M-[
    :ed_unassigned,
    # 220 M-\
    :ed_unassigned,
    # 221 M-]
    :ed_unassigned,
    # 222 M-^
    :ed_unassigned,
    # 223 M-_
    :ed_unassigned,
    # 224 M-`
    :ed_unassigned,
    # 225 M-a
    :ed_unassigned,
    # 226 M-b
    :ed_prev_word,
    # 227 M-c
    :em_capitol_case,
    # 228 M-d
    :em_delete_next_word,
    # 229 M-e
    :ed_unassigned,
    # 230 M-f
    :em_next_word,
    # 231 M-g
    :ed_unassigned,
    # 232 M-h
    :ed_unassigned,
    # 233 M-i
    :ed_unassigned,
    # 234 M-j
    :ed_unassigned,
    # 235 M-k
    :ed_unassigned,
    # 236 M-l
    :em_lower_case,
    # 237 M-m
    :ed_unassigned,
    # 238 M-n
    :vi_search_next,
    # 239 M-o
    :ed_unassigned,
    # 240 M-p
    :vi_search_prev,
    # 241 M-q
    :ed_unassigned,
    # 242 M-r
    :ed_unassigned,
    # 243 M-s
    :ed_unassigned,
    # 244 M-t
    :ed_transpose_words,
    # 245 M-u
    :em_upper_case,
    # 246 M-v
    :ed_unassigned,
    # 247 M-w
    :ed_unassigned,
    # 248 M-x
    :ed_unassigned,
    # 249 M-y
    :ed_unassigned,
    # 250 M-z
    :ed_unassigned,
    # 251 M-{
    :ed_unassigned,
    # 252 M-|
    :ed_unassigned,
    # 253 M-}
    :ed_unassigned,
    # 254 M-~
    :ed_unassigned,
    # 255 M-^?
    :ed_delete_prev_word
    # EOF
  ]
end
