module Reline::KeyActor
  VI_COMMAND_MAPPING = [
    #   0 ^@
    :ed_unassigned,
    #   1 ^A
    :ed_move_to_beg,
    #   2 ^B
    :ed_unassigned,
    #   3 ^C
    :ed_ignore,
    #   4 ^D
    :vi_end_of_transmission,
    #   5 ^E
    :ed_move_to_end,
    #   6 ^F
    :ed_unassigned,
    #   7 ^G
    :ed_unassigned,
    #   8 ^H
    :ed_prev_char,
    #   9 ^I
    :ed_unassigned,
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
    :ed_ignore,
    #  18 ^R
    :vi_search_prev,
    #  19 ^S
    :ed_ignore,
    #  20 ^T
    :ed_transpose_chars,
    #  21 ^U
    :vi_kill_line_prev,
    #  22 ^V
    :ed_quoted_insert,
    #  23 ^W
    :ed_delete_prev_word,
    #  24 ^X
    :ed_unassigned,
    #  25 ^Y
    :em_yank,
    #  26 ^Z
    :ed_unassigned,
    #  27 ^[
    :ed_unassigned,
    #  28 ^\
    :ed_ignore,
    #  29 ^]
    :ed_unassigned,
    #  30 ^^
    :ed_unassigned,
    #  31 ^_
    :ed_unassigned,
    #  32 SPACE
    :ed_next_char,
    #  33 !
    :ed_unassigned,
    #  34 "
    :ed_unassigned,
    #  35 #
    :vi_comment_out,
    #  36 $
    :ed_move_to_end,
    #  37 %
    :ed_unassigned,
    #  38 &
    :ed_unassigned,
    #  39 '
    :ed_unassigned,
    #  40 (
    :ed_unassigned,
    #  41 )
    :ed_unassigned,
    #  42 *
    :ed_unassigned,
    #  43 +
    :ed_next_history,
    #  44 ,
    :ed_unassigned,
    #  45 -
    :ed_prev_history,
    #  46 .
    :ed_unassigned,
    #  47 /
    :vi_search_prev,
    #  48 0
    :vi_zero,
    #  49 1
    :ed_argument_digit,
    #  50 2
    :ed_argument_digit,
    #  51 3
    :ed_argument_digit,
    #  52 4
    :ed_argument_digit,
    #  53 5
    :ed_argument_digit,
    #  54 6
    :ed_argument_digit,
    #  55 7
    :ed_argument_digit,
    #  56 8
    :ed_argument_digit,
    #  57 9
    :ed_argument_digit,
    #  58 :
    :ed_unassigned,
    #  59 ;
    :ed_unassigned,
    #  60 <
    :ed_unassigned,
    #  61 =
    :ed_unassigned,
    #  62 >
    :ed_unassigned,
    #  63 ?
    :vi_search_next,
    #  64 @
    :vi_alias,
    #  65 A
    :vi_add_at_eol,
    #  66 B
    :vi_prev_big_word,
    #  67 C
    :vi_change_to_eol,
    #  68 D
    :ed_kill_line,
    #  69 E
    :vi_end_big_word,
    #  70 F
    :vi_prev_char,
    #  71 G
    :vi_to_history_line,
    #  72 H
    :ed_unassigned,
    #  73 I
    :vi_insert_at_bol,
    #  74 J
    :vi_join_lines,
    #  75 K
    :vi_search_prev,
    #  76 L
    :ed_unassigned,
    #  77 M
    :ed_unassigned,
    #  78 N
    :ed_unassigned,
    #  79 O
    :ed_unassigned,
    #  80 P
    :vi_paste_prev,
    #  81 Q
    :ed_unassigned,
    #  82 R
    :ed_unassigned,
    #  83 S
    :ed_unassigned,
    #  84 T
    :vi_to_prev_char,
    #  85 U
    :ed_unassigned,
    #  86 V
    :ed_unassigned,
    #  87 W
    :vi_next_big_word,
    #  88 X
    :ed_delete_prev_char,
    #  89 Y
    :ed_unassigned,
    #  90 Z
    :ed_unassigned,
    #  91 [
    :ed_unassigned,
    #  92 \
    :ed_unassigned,
    #  93 ]
    :ed_unassigned,
    #  94 ^
    :vi_first_print,
    #  95 _
    :ed_unassigned,
    #  96 `
    :ed_unassigned,
    #  97 a
    :vi_add,
    #  98 b
    :vi_prev_word,
    #  99 c
    :vi_change_meta,
    # 100 d
    :vi_delete_meta,
    # 101 e
    :vi_end_word,
    # 102 f
    :vi_next_char,
    # 103 g
    :ed_unassigned,
    # 104 h
    :ed_prev_char,
    # 105 i
    :vi_insert,
    # 106 j
    :ed_next_history,
    # 107 k
    :ed_prev_history,
    # 108 l
    :ed_next_char,
    # 109 m
    :ed_unassigned,
    # 110 n
    :ed_unassigned,
    # 111 o
    :ed_unassigned,
    # 112 p
    :vi_paste_next,
    # 113 q
    :ed_unassigned,
    # 114 r
    :vi_replace_char,
    # 115 s
    :ed_unassigned,
    # 116 t
    :vi_to_next_char,
    # 117 u
    :ed_unassigned,
    # 118 v
    :vi_histedit,
    # 119 w
    :vi_next_word,
    # 120 x
    :ed_delete_next_char,
    # 121 y
    :vi_yank,
    # 122 z
    :ed_unassigned,
    # 123 {
    :ed_unassigned,
    # 124 |
    :vi_to_column,
    # 125 }
    :ed_unassigned,
    # 126 ~
    :ed_unassigned,
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
    :ed_unassigned,
    # 137 M-^I
    :ed_unassigned,
    # 138 M-^J
    :ed_unassigned,
    # 139 M-^K
    :ed_unassigned,
    # 140 M-^L
    :ed_unassigned,
    # 141 M-^M
    :ed_unassigned,
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
    :ed_unassigned,
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
    :ed_unassigned,
    # 160 M-SPACE
    :ed_unassigned,
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
    :ed_unassigned,
    # 177 M-1
    :ed_unassigned,
    # 178 M-2
    :ed_unassigned,
    # 179 M-3
    :ed_unassigned,
    # 180 M-4
    :ed_unassigned,
    # 181 M-5
    :ed_unassigned,
    # 182 M-6
    :ed_unassigned,
    # 183 M-7
    :ed_unassigned,
    # 184 M-8
    :ed_unassigned,
    # 185 M-9
    :ed_unassigned,
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
    :ed_unassigned,
    # 195 M-C
    :ed_unassigned,
    # 196 M-D
    :ed_unassigned,
    # 197 M-E
    :ed_unassigned,
    # 198 M-F
    :ed_unassigned,
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
    :ed_unassigned,
    # 205 M-M
    :ed_unassigned,
    # 206 M-N
    :ed_unassigned,
    # 207 M-O
    :ed_unassigned,
    # 208 M-P
    :ed_unassigned,
    # 209 M-Q
    :ed_unassigned,
    # 210 M-R
    :ed_unassigned,
    # 211 M-S
    :ed_unassigned,
    # 212 M-T
    :ed_unassigned,
    # 213 M-U
    :ed_unassigned,
    # 214 M-V
    :ed_unassigned,
    # 215 M-W
    :ed_unassigned,
    # 216 M-X
    :ed_unassigned,
    # 217 M-Y
    :ed_unassigned,
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
    :ed_unassigned,
    # 227 M-c
    :ed_unassigned,
    # 228 M-d
    :ed_unassigned,
    # 229 M-e
    :ed_unassigned,
    # 230 M-f
    :ed_unassigned,
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
    :ed_unassigned,
    # 237 M-m
    :ed_unassigned,
    # 238 M-n
    :ed_unassigned,
    # 239 M-o
    :ed_unassigned,
    # 240 M-p
    :ed_unassigned,
    # 241 M-q
    :ed_unassigned,
    # 242 M-r
    :ed_unassigned,
    # 243 M-s
    :ed_unassigned,
    # 244 M-t
    :ed_unassigned,
    # 245 M-u
    :ed_unassigned,
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
    :ed_unassigned
    # EOF
  ]
end

