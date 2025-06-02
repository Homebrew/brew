#ifndef ONIGMO_H
#define ONIGMO_H
/**********************************************************************
  onigmo.h - Onigmo (Oniguruma-mod) (regular expression library)
**********************************************************************/
/*-
 * Copyright (c) 2002-2009  K.Kosako  <sndgk393 AT ybb DOT ne DOT jp>
 * Copyright (c) 2011-2017  K.Takata  <kentkt AT csc DOT jp>
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 */

#ifdef __cplusplus
extern "C" {
# if 0
} /* satisfy cc-mode */
# endif
#endif

#define ONIGMO_VERSION_MAJOR   6
#define ONIGMO_VERSION_MINOR   1
#define ONIGMO_VERSION_TEENY   3

#ifndef ONIG_EXTERN
# ifdef RUBY_EXTERN
#  define ONIG_EXTERN   RUBY_EXTERN
# else
#  if defined(_WIN32) && !defined(__GNUC__)
#   if defined(EXPORT) || defined(RUBY_EXPORT)
#    define ONIG_EXTERN   extern __declspec(dllexport)
#   else
#    define ONIG_EXTERN   extern __declspec(dllimport)
#   endif
#  endif
# endif
#endif

#ifndef ONIG_EXTERN
# define ONIG_EXTERN   extern
#endif

#ifndef RUBY
# ifndef RUBY_SYMBOL_EXPORT_BEGIN
#  define RUBY_SYMBOL_EXPORT_BEGIN
#  define RUBY_SYMBOL_EXPORT_END
# endif
#endif

RUBY_SYMBOL_EXPORT_BEGIN

#include <stddef.h>		/* for size_t */

/* PART: character encoding */

#ifndef ONIG_ESCAPE_UCHAR_COLLISION
# define UChar OnigUChar
#endif

typedef unsigned char  OnigUChar;
typedef unsigned int   OnigCodePoint;
typedef unsigned int   OnigCtype;
typedef size_t         OnigDistance;
typedef ptrdiff_t      OnigPosition;

#define ONIG_INFINITE_DISTANCE  ~((OnigDistance )0)

/*
 * Onig casefold/case mapping flags and related definitions
 *
 * Subfields (starting with 0 at LSB):
 *   0-2: Code point count in casefold.h
 *   3-12: Index into SpecialCaseMapping array in casefold.h
 *   13-22: Case folding/mapping flags
 */
typedef unsigned int OnigCaseFoldType; /* case fold flag */

ONIG_EXTERN OnigCaseFoldType OnigDefaultCaseFoldFlag;

/* bits for actual code point count; 3 bits is more than enough, currently only 2 used */
#define OnigCodePointMaskWidth    3
#define OnigCodePointMask     ((1<<OnigCodePointMaskWidth)-1)
#define OnigCodePointCount(n) ((n)&OnigCodePointMask)
#define OnigCaseFoldFlags(n) ((n)&~OnigCodePointMask)

/* #define ONIGENC_CASE_FOLD_HIRAGANA_KATAKANA  (1<<1) */ /* no longer usable with these values! */
/* #define ONIGENC_CASE_FOLD_KATAKANA_WIDTH     (1<<2) */ /* no longer usable with these values! */

/* bits for index into table with separate titlecase mappings */
/* 10 bits provide 1024 values */
#define OnigSpecialIndexShift 3
#define OnigSpecialIndexWidth 10

#define ONIGENC_CASE_UPCASE                     (1<<13) /* has/needs uppercase mapping */
#define ONIGENC_CASE_DOWNCASE                   (1<<14) /* has/needs lowercase mapping */
#define ONIGENC_CASE_TITLECASE                  (1<<15) /* has/needs (special) titlecase mapping */
#define ONIGENC_CASE_SPECIAL_OFFSET             3       /* offset in bits from ONIGENC_CASE to ONIGENC_CASE_SPECIAL */
#define ONIGENC_CASE_UP_SPECIAL                 (1<<16) /* has special upcase mapping */
#define ONIGENC_CASE_DOWN_SPECIAL               (1<<17) /* has special downcase mapping */
#define ONIGENC_CASE_MODIFIED                   (1<<18) /* data has been modified */
#define ONIGENC_CASE_FOLD                       (1<<19) /* has/needs case folding */

#define ONIGENC_CASE_FOLD_TURKISH_AZERI         (1<<20) /* needs mapping specific to Turkic languages; better not change original value! */

#define ONIGENC_CASE_FOLD_LITHUANIAN            (1<<21) /* needs Lithuanian-specific mapping */
#define ONIGENC_CASE_ASCII_ONLY                 (1<<22) /* only modify ASCII range */
#define ONIGENC_CASE_IS_TITLECASE               (1<<23) /* character itself is already titlecase */

#define INTERNAL_ONIGENC_CASE_FOLD_MULTI_CHAR   (1<<30) /* better not change original value! */

#define ONIGENC_CASE_FOLD_MIN      INTERNAL_ONIGENC_CASE_FOLD_MULTI_CHAR
#define ONIGENC_CASE_FOLD_DEFAULT  OnigDefaultCaseFoldFlag


#define ONIGENC_MAX_COMP_CASE_FOLD_CODE_LEN       3
#define ONIGENC_GET_CASE_FOLD_CODES_MAX_NUM      13
/* 13 => Unicode:0x1ffc */

/* code range */
#define ONIGENC_CODE_RANGE_NUM(range)     ((int )range[0])
#define ONIGENC_CODE_RANGE_FROM(range,i)  range[((i)*2) + 1]
#define ONIGENC_CODE_RANGE_TO(range,i)    range[((i)*2) + 2]

typedef struct {
  int byte_len;  /* argument(original) character(s) byte length */
  int code_len;  /* number of code */
  OnigCodePoint code[ONIGENC_MAX_COMP_CASE_FOLD_CODE_LEN];
} OnigCaseFoldCodeItem;

typedef struct {
  OnigCodePoint esc;
  OnigCodePoint anychar;
  OnigCodePoint anytime;
  OnigCodePoint zero_or_one_time;
  OnigCodePoint one_or_more_time;
  OnigCodePoint anychar_anytime;
} OnigMetaCharTableType;

typedef int (*OnigApplyAllCaseFoldFunc)(OnigCodePoint from, OnigCodePoint* to, int to_len, void* arg);

typedef struct OnigEncodingTypeST {
  int    (*precise_mbc_enc_len)(const OnigUChar* p,const OnigUChar* e, const struct OnigEncodingTypeST* enc);
  const char*   name;
  int           max_enc_len;
  int           min_enc_len;
  int    (*is_mbc_newline)(const OnigUChar* p, const OnigUChar* end, const struct OnigEncodingTypeST* enc);
  OnigCodePoint (*mbc_to_code)(const OnigUChar* p, const OnigUChar* end, const struct OnigEncodingTypeST* enc);
  int    (*code_to_mbclen)(OnigCodePoint code, const struct OnigEncodingTypeST* enc);
  int    (*code_to_mbc)(OnigCodePoint code, OnigUChar *buf, const struct OnigEncodingTypeST* enc);
  int    (*mbc_case_fold)(OnigCaseFoldType flag, const OnigUChar** pp, const OnigUChar* end, OnigUChar* to, const struct OnigEncodingTypeST* enc);
  int    (*apply_all_case_fold)(OnigCaseFoldType flag, OnigApplyAllCaseFoldFunc f, void* arg, const struct OnigEncodingTypeST* enc);
  int    (*get_case_fold_codes_by_str)(OnigCaseFoldType flag, const OnigUChar* p, const OnigUChar* end, OnigCaseFoldCodeItem acs[], const struct OnigEncodingTypeST* enc);
  int    (*property_name_to_ctype)(const struct OnigEncodingTypeST* enc, const OnigUChar* p, const OnigUChar* end);
  int    (*is_code_ctype)(OnigCodePoint code, OnigCtype ctype, const struct OnigEncodingTypeST* enc);
  int    (*get_ctype_code_range)(OnigCtype ctype, OnigCodePoint* sb_out, const OnigCodePoint* ranges[], const struct OnigEncodingTypeST* enc);
  OnigUChar* (*left_adjust_char_head)(const OnigUChar* start, const OnigUChar* p, const OnigUChar* end, const struct OnigEncodingTypeST* enc);
  int    (*is_allowed_reverse_match)(const OnigUChar* p, const OnigUChar* end, const struct OnigEncodingTypeST* enc);
  int    (*case_map)(OnigCaseFoldType* flagP, const OnigUChar** pp, const OnigUChar* end, OnigUChar* to, OnigUChar* to_end, const struct OnigEncodingTypeST* enc);
  int ruby_encoding_index;
  unsigned int  flags;
} OnigEncodingType;

typedef const OnigEncodingType* OnigEncoding;

ONIG_EXTERN const OnigEncodingType OnigEncodingASCII;
#ifndef RUBY
ONIG_EXTERN const OnigEncodingType OnigEncodingISO_8859_1;
ONIG_EXTERN const OnigEncodingType OnigEncodingISO_8859_2;
ONIG_EXTERN const OnigEncodingType OnigEncodingISO_8859_3;
ONIG_EXTERN const OnigEncodingType OnigEncodingISO_8859_4;
ONIG_EXTERN const OnigEncodingType OnigEncodingISO_8859_5;
ONIG_EXTERN const OnigEncodingType OnigEncodingISO_8859_6;
ONIG_EXTERN const OnigEncodingType OnigEncodingISO_8859_7;
ONIG_EXTERN const OnigEncodingType OnigEncodingISO_8859_8;
ONIG_EXTERN const OnigEncodingType OnigEncodingISO_8859_9;
ONIG_EXTERN const OnigEncodingType OnigEncodingISO_8859_10;
ONIG_EXTERN const OnigEncodingType OnigEncodingISO_8859_11;
ONIG_EXTERN const OnigEncodingType OnigEncodingISO_8859_13;
ONIG_EXTERN const OnigEncodingType OnigEncodingISO_8859_14;
ONIG_EXTERN const OnigEncodingType OnigEncodingISO_8859_15;
ONIG_EXTERN const OnigEncodingType OnigEncodingISO_8859_16;
ONIG_EXTERN const OnigEncodingType OnigEncodingUTF_8;
ONIG_EXTERN const OnigEncodingType OnigEncodingUTF_16BE;
ONIG_EXTERN const OnigEncodingType OnigEncodingUTF_16LE;
ONIG_EXTERN const OnigEncodingType OnigEncodingUTF_32BE;
ONIG_EXTERN const OnigEncodingType OnigEncodingUTF_32LE;
ONIG_EXTERN const OnigEncodingType OnigEncodingEUC_JP;
ONIG_EXTERN const OnigEncodingType OnigEncodingEUC_TW;
ONIG_EXTERN const OnigEncodingType OnigEncodingEUC_KR;
ONIG_EXTERN const OnigEncodingType OnigEncodingEUC_CN;
ONIG_EXTERN const OnigEncodingType OnigEncodingShift_JIS;
ONIG_EXTERN const OnigEncodingType OnigEncodingWindows_31J;
/* ONIG_EXTERN const OnigEncodingType OnigEncodingKOI8; */
ONIG_EXTERN const OnigEncodingType OnigEncodingKOI8_R;
ONIG_EXTERN const OnigEncodingType OnigEncodingKOI8_U;
ONIG_EXTERN const OnigEncodingType OnigEncodingWindows_1250;
ONIG_EXTERN const OnigEncodingType OnigEncodingWindows_1251;
ONIG_EXTERN const OnigEncodingType OnigEncodingWindows_1252;
ONIG_EXTERN const OnigEncodingType OnigEncodingWindows_1253;
ONIG_EXTERN const OnigEncodingType OnigEncodingWindows_1254;
ONIG_EXTERN const OnigEncodingType OnigEncodingWindows_1257;
ONIG_EXTERN const OnigEncodingType OnigEncodingBIG5;
ONIG_EXTERN const OnigEncodingType OnigEncodingGB18030;
#endif /* RUBY */

#define ONIG_ENCODING_ASCII        (&OnigEncodingASCII)
#ifndef RUBY
# define ONIG_ENCODING_ISO_8859_1   (&OnigEncodingISO_8859_1)
# define ONIG_ENCODING_ISO_8859_2   (&OnigEncodingISO_8859_2)
# define ONIG_ENCODING_ISO_8859_3   (&OnigEncodingISO_8859_3)
# define ONIG_ENCODING_ISO_8859_4   (&OnigEncodingISO_8859_4)
# define ONIG_ENCODING_ISO_8859_5   (&OnigEncodingISO_8859_5)
# define ONIG_ENCODING_ISO_8859_6   (&OnigEncodingISO_8859_6)
# define ONIG_ENCODING_ISO_8859_7   (&OnigEncodingISO_8859_7)
# define ONIG_ENCODING_ISO_8859_8   (&OnigEncodingISO_8859_8)
# define ONIG_ENCODING_ISO_8859_9   (&OnigEncodingISO_8859_9)
# define ONIG_ENCODING_ISO_8859_10  (&OnigEncodingISO_8859_10)
# define ONIG_ENCODING_ISO_8859_11  (&OnigEncodingISO_8859_11)
# define ONIG_ENCODING_ISO_8859_13  (&OnigEncodingISO_8859_13)
# define ONIG_ENCODING_ISO_8859_14  (&OnigEncodingISO_8859_14)
# define ONIG_ENCODING_ISO_8859_15  (&OnigEncodingISO_8859_15)
# define ONIG_ENCODING_ISO_8859_16  (&OnigEncodingISO_8859_16)
# define ONIG_ENCODING_UTF_8        (&OnigEncodingUTF_8)
# define ONIG_ENCODING_UTF_16BE     (&OnigEncodingUTF_16BE)
# define ONIG_ENCODING_UTF_16LE     (&OnigEncodingUTF_16LE)
# define ONIG_ENCODING_UTF_32BE     (&OnigEncodingUTF_32BE)
# define ONIG_ENCODING_UTF_32LE     (&OnigEncodingUTF_32LE)
# define ONIG_ENCODING_EUC_JP       (&OnigEncodingEUC_JP)
# define ONIG_ENCODING_EUC_TW       (&OnigEncodingEUC_TW)
# define ONIG_ENCODING_EUC_KR       (&OnigEncodingEUC_KR)
# define ONIG_ENCODING_EUC_CN       (&OnigEncodingEUC_CN)
# define ONIG_ENCODING_SHIFT_JIS    (&OnigEncodingShift_JIS)
# define ONIG_ENCODING_WINDOWS_31J  (&OnigEncodingWindows_31J)
/* # define ONIG_ENCODING_KOI8         (&OnigEncodingKOI8) */
# define ONIG_ENCODING_KOI8_R       (&OnigEncodingKOI8_R)
# define ONIG_ENCODING_KOI8_U       (&OnigEncodingKOI8_U)
# define ONIG_ENCODING_WINDOWS_1250 (&OnigEncodingWindows_1250)
# define ONIG_ENCODING_WINDOWS_1251 (&OnigEncodingWindows_1251)
# define ONIG_ENCODING_WINDOWS_1252 (&OnigEncodingWindows_1252)
# define ONIG_ENCODING_WINDOWS_1253 (&OnigEncodingWindows_1253)
# define ONIG_ENCODING_WINDOWS_1254 (&OnigEncodingWindows_1254)
# define ONIG_ENCODING_WINDOWS_1257 (&OnigEncodingWindows_1257)
# define ONIG_ENCODING_BIG5         (&OnigEncodingBIG5)
# define ONIG_ENCODING_GB18030      (&OnigEncodingGB18030)

/* old names */
# define ONIG_ENCODING_SJIS         ONIG_ENCODING_SHIFT_JIS
# define ONIG_ENCODING_CP932        ONIG_ENCODING_WINDOWS_31J
# define ONIG_ENCODING_CP1250       ONIG_ENCODING_WINDOWS_1250
# define ONIG_ENCODING_CP1251       ONIG_ENCODING_WINDOWS_1251
# define ONIG_ENCODING_CP1252       ONIG_ENCODING_WINDOWS_1252
# define ONIG_ENCODING_CP1253       ONIG_ENCODING_WINDOWS_1253
# define ONIG_ENCODING_CP1254       ONIG_ENCODING_WINDOWS_1254
# define ONIG_ENCODING_CP1257       ONIG_ENCODING_WINDOWS_1257
# define ONIG_ENCODING_UTF8         ONIG_ENCODING_UTF_8
# define ONIG_ENCODING_UTF16_BE     ONIG_ENCODING_UTF_16BE
# define ONIG_ENCODING_UTF16_LE     ONIG_ENCODING_UTF_16LE
# define ONIG_ENCODING_UTF32_BE     ONIG_ENCODING_UTF_32BE
# define ONIG_ENCODING_UTF32_LE     ONIG_ENCODING_UTF_32LE
#endif /* RUBY */

#define ONIG_ENCODING_UNDEF    ((OnigEncoding )0)

/* this declaration needs to be here because it is used in string.c in Ruby */
ONIG_EXTERN
int onigenc_ascii_only_case_map(OnigCaseFoldType* flagP, const OnigUChar** pp, const OnigUChar* end, OnigUChar* to, OnigUChar* to_end, const struct OnigEncodingTypeST* enc);


/* work size */
#define ONIGENC_CODE_TO_MBC_MAXLEN       7
#define ONIGENC_MBC_CASE_FOLD_MAXLEN    18
/* 18: 6(max-byte) * 3(case-fold chars) */

/* character types */
#define ONIGENC_CTYPE_NEWLINE   0
#define ONIGENC_CTYPE_ALPHA     1
#define ONIGENC_CTYPE_BLANK     2
#define ONIGENC_CTYPE_CNTRL     3
#define ONIGENC_CTYPE_DIGIT     4
#define ONIGENC_CTYPE_GRAPH     5
#define ONIGENC_CTYPE_LOWER     6
#define ONIGENC_CTYPE_PRINT     7
#define ONIGENC_CTYPE_PUNCT     8
#define ONIGENC_CTYPE_SPACE     9
#define ONIGENC_CTYPE_UPPER    10
#define ONIGENC_CTYPE_XDIGIT   11
#define ONIGENC_CTYPE_WORD     12
#define ONIGENC_CTYPE_ALNUM    13  /* alpha || digit */
#define ONIGENC_CTYPE_ASCII    14
#define ONIGENC_MAX_STD_CTYPE  ONIGENC_CTYPE_ASCII

/* flags */
#define ONIGENC_FLAG_NONE       0U
#define ONIGENC_FLAG_UNICODE    1U

#define onig_enc_len(enc,p,e)          ONIGENC_MBC_ENC_LEN(enc, p, e)

#define ONIGENC_IS_UNDEF(enc)          ((enc) == ONIG_ENCODING_UNDEF)
#define ONIGENC_IS_SINGLEBYTE(enc)     (ONIGENC_MBC_MAXLEN(enc) == 1)
#define ONIGENC_IS_MBC_HEAD(enc,p,e)   (ONIGENC_MBC_ENC_LEN(enc,p,e) != 1)
#define ONIGENC_IS_MBC_ASCII(p)           (*(p)   < 128)
#define ONIGENC_IS_CODE_ASCII(code)       ((code) < 128)
#define ONIGENC_IS_MBC_WORD(enc,s,end) \
   ONIGENC_IS_CODE_WORD(enc,ONIGENC_MBC_TO_CODE(enc,s,end))
#define ONIGENC_IS_MBC_ASCII_WORD(enc,s,end) \
   onigenc_ascii_is_code_ctype( \
	ONIGENC_MBC_TO_CODE(enc,s,end),ONIGENC_CTYPE_WORD,enc)
#define ONIGENC_IS_UNICODE(enc)        ((enc)->flags & ONIGENC_FLAG_UNICODE)


#define ONIGENC_NAME(enc)                      ((enc)->name)

#define ONIGENC_MBC_CASE_FOLD(enc,flag,pp,end,buf) \
  (enc)->mbc_case_fold(flag,(const OnigUChar** )pp,end,buf,enc)
#define ONIGENC_IS_ALLOWED_REVERSE_MATCH(enc,s,end) \
        (enc)->is_allowed_reverse_match(s,end,enc)
#define ONIGENC_LEFT_ADJUST_CHAR_HEAD(enc,start,s,end) \
        (enc)->left_adjust_char_head(start, s, end, enc)
#define ONIGENC_APPLY_ALL_CASE_FOLD(enc,case_fold_flag,f,arg) \
        (enc)->apply_all_case_fold(case_fold_flag,f,arg,enc)
#define ONIGENC_GET_CASE_FOLD_CODES_BY_STR(enc,case_fold_flag,p,end,acs) \
       (enc)->get_case_fold_codes_by_str(case_fold_flag,p,end,acs,enc)
#define ONIGENC_STEP_BACK(enc,start,s,end,n) \
        onigenc_step_back((enc),(start),(s),(end),(n))

#define ONIGENC_CONSTRUCT_MBCLEN_CHARFOUND(n)   (n)
#define ONIGENC_MBCLEN_CHARFOUND_P(r)           (0 < (r))
#define ONIGENC_MBCLEN_CHARFOUND_LEN(r)         (r)

#define ONIGENC_CONSTRUCT_MBCLEN_INVALID()      (-1)
#define ONIGENC_MBCLEN_INVALID_P(r)             ((r) == -1)

#define ONIGENC_CONSTRUCT_MBCLEN_NEEDMORE(n)    (-1-(n))
#define ONIGENC_MBCLEN_NEEDMORE_P(r)            ((r) < -1)
#define ONIGENC_MBCLEN_NEEDMORE_LEN(r)          (-1-(r))

#define ONIGENC_PRECISE_MBC_ENC_LEN(enc,p,e)   (enc)->precise_mbc_enc_len(p,e,enc)

ONIG_EXTERN
int onigenc_mbclen_approximate(const OnigUChar* p,const OnigUChar* e, const struct OnigEncodingTypeST* enc);

#define ONIGENC_MBC_ENC_LEN(enc,p,e)           onigenc_mbclen_approximate(p,e,enc)
#define ONIGENC_MBC_MAXLEN(enc)               ((enc)->max_enc_len)
#define ONIGENC_MBC_MAXLEN_DIST(enc)           ONIGENC_MBC_MAXLEN(enc)
#define ONIGENC_MBC_MINLEN(enc)               ((enc)->min_enc_len)
#define ONIGENC_IS_MBC_NEWLINE(enc,p,end)      (enc)->is_mbc_newline((p),(end),enc)
#define ONIGENC_MBC_TO_CODE(enc,p,end)         (enc)->mbc_to_code((p),(end),enc)
#define ONIGENC_CODE_TO_MBCLEN(enc,code)       (enc)->code_to_mbclen(code,enc)
#define ONIGENC_CODE_TO_MBC(enc,code,buf)      (enc)->code_to_mbc(code,buf,enc)
#define ONIGENC_PROPERTY_NAME_TO_CTYPE(enc,p,end) \
  (enc)->property_name_to_ctype(enc,p,end)

#define ONIGENC_IS_CODE_CTYPE(enc,code,ctype)  (enc)->is_code_ctype(code,ctype,enc)

#define ONIGENC_IS_CODE_NEWLINE(enc,code) \
        ONIGENC_IS_CODE_CTYPE(enc,code,ONIGENC_CTYPE_NEWLINE)
#define ONIGENC_IS_CODE_GRAPH(enc,code) \
        ONIGENC_IS_CODE_CTYPE(enc,code,ONIGENC_CTYPE_GRAPH)
#define ONIGENC_IS_CODE_PRINT(enc,code) \
        ONIGENC_IS_CODE_CTYPE(enc,code,ONIGENC_CTYPE_PRINT)
#define ONIGENC_IS_CODE_ALNUM(enc,code) \
        ONIGENC_IS_CODE_CTYPE(enc,code,ONIGENC_CTYPE_ALNUM)
#define ONIGENC_IS_CODE_ALPHA(enc,code) \
        ONIGENC_IS_CODE_CTYPE(enc,code,ONIGENC_CTYPE_ALPHA)
#define ONIGENC_IS_CODE_LOWER(enc,code) \
        ONIGENC_IS_CODE_CTYPE(enc,code,ONIGENC_CTYPE_LOWER)
#define ONIGENC_IS_CODE_UPPER(enc,code) \
        ONIGENC_IS_CODE_CTYPE(enc,code,ONIGENC_CTYPE_UPPER)
#define ONIGENC_IS_CODE_CNTRL(enc,code) \
        ONIGENC_IS_CODE_CTYPE(enc,code,ONIGENC_CTYPE_CNTRL)
#define ONIGENC_IS_CODE_PUNCT(enc,code) \
        ONIGENC_IS_CODE_CTYPE(enc,code,ONIGENC_CTYPE_PUNCT)
#define ONIGENC_IS_CODE_SPACE(enc,code) \
        ONIGENC_IS_CODE_CTYPE(enc,code,ONIGENC_CTYPE_SPACE)
#define ONIGENC_IS_CODE_BLANK(enc,code) \
        ONIGENC_IS_CODE_CTYPE(enc,code,ONIGENC_CTYPE_BLANK)
#define ONIGENC_IS_CODE_DIGIT(enc,code) \
        ONIGENC_IS_CODE_CTYPE(enc,code,ONIGENC_CTYPE_DIGIT)
#define ONIGENC_IS_CODE_XDIGIT(enc,code) \
        ONIGENC_IS_CODE_CTYPE(enc,code,ONIGENC_CTYPE_XDIGIT)
#define ONIGENC_IS_CODE_WORD(enc,code) \
        ONIGENC_IS_CODE_CTYPE(enc,code,ONIGENC_CTYPE_WORD)

#define ONIGENC_GET_CTYPE_CODE_RANGE(enc,ctype,sbout,ranges) \
        (enc)->get_ctype_code_range(ctype,sbout,ranges,enc)

ONIG_EXTERN
OnigUChar* onigenc_step_back(OnigEncoding enc, const OnigUChar* start, const OnigUChar* s, const OnigUChar* end, int n);


/* encoding API */
ONIG_EXTERN
int onigenc_init(void);
ONIG_EXTERN
int onigenc_set_default_encoding(OnigEncoding enc);
ONIG_EXTERN
OnigEncoding onigenc_get_default_encoding(void);
ONIG_EXTERN
OnigUChar* onigenc_get_right_adjust_char_head_with_prev(OnigEncoding enc, const OnigUChar* start, const OnigUChar* s, const OnigUChar* end, const OnigUChar** prev);
ONIG_EXTERN
OnigUChar* onigenc_get_prev_char_head(OnigEncoding enc, const OnigUChar* start, const OnigUChar* s, const OnigUChar* end);
ONIG_EXTERN
OnigUChar* onigenc_get_left_adjust_char_head(OnigEncoding enc, const OnigUChar* start, const OnigUChar* s, const OnigUChar* end);
ONIG_EXTERN
OnigUChar* onigenc_get_right_adjust_char_head(OnigEncoding enc, const OnigUChar* start, const OnigUChar* s, const OnigUChar* end);
ONIG_EXTERN
int onigenc_strlen(OnigEncoding enc, const OnigUChar* p, const OnigUChar* end);
ONIG_EXTERN
int onigenc_strlen_null(OnigEncoding enc, const OnigUChar* p);
ONIG_EXTERN
int onigenc_str_bytelen_null(OnigEncoding enc, const OnigUChar* p);



/* PART: regular expression */

/* config parameters */
#define ONIG_NREGION                          4
#define ONIG_MAX_CAPTURE_GROUP_NUM         32767
#define ONIG_MAX_BACKREF_NUM                1000
#define ONIG_MAX_REPEAT_NUM               100000
#define ONIG_MAX_MULTI_BYTE_RANGES_NUM     10000
/* constants */
#define ONIG_MAX_ERROR_MESSAGE_LEN            90

typedef unsigned int        OnigOptionType;

#define ONIG_OPTION_DEFAULT            ONIG_OPTION_NONE

/* options */
#define ONIG_OPTION_NONE                 0U
#define ONIG_OPTION_IGNORECASE           1U
#define ONIG_OPTION_EXTEND               (ONIG_OPTION_IGNORECASE         << 1)
#define ONIG_OPTION_MULTILINE            (ONIG_OPTION_EXTEND             << 1)
#define ONIG_OPTION_DOTALL                ONIG_OPTION_MULTILINE
#define ONIG_OPTION_SINGLELINE           (ONIG_OPTION_MULTILINE          << 1)
#define ONIG_OPTION_FIND_LONGEST         (ONIG_OPTION_SINGLELINE         << 1)
#define ONIG_OPTION_FIND_NOT_EMPTY       (ONIG_OPTION_FIND_LONGEST       << 1)
#define ONIG_OPTION_NEGATE_SINGLELINE    (ONIG_OPTION_FIND_NOT_EMPTY     << 1)
#define ONIG_OPTION_DONT_CAPTURE_GROUP   (ONIG_OPTION_NEGATE_SINGLELINE  << 1)
#define ONIG_OPTION_CAPTURE_GROUP        (ONIG_OPTION_DONT_CAPTURE_GROUP << 1)
/* options (search time) */
#define ONIG_OPTION_NOTBOL               (ONIG_OPTION_CAPTURE_GROUP << 1)
#define ONIG_OPTION_NOTEOL               (ONIG_OPTION_NOTBOL << 1)
#define ONIG_OPTION_NOTBOS               (ONIG_OPTION_NOTEOL << 1)
#define ONIG_OPTION_NOTEOS               (ONIG_OPTION_NOTBOS << 1)
/* options (ctype range) */
#define ONIG_OPTION_ASCII_RANGE          (ONIG_OPTION_NOTEOS << 1)
#define ONIG_OPTION_POSIX_BRACKET_ALL_RANGE (ONIG_OPTION_ASCII_RANGE << 1)
#define ONIG_OPTION_WORD_BOUND_ALL_RANGE    (ONIG_OPTION_POSIX_BRACKET_ALL_RANGE << 1)
/* options (newline) */
#define ONIG_OPTION_NEWLINE_CRLF         (ONIG_OPTION_WORD_BOUND_ALL_RANGE << 1)
#define ONIG_OPTION_MAXBIT               ONIG_OPTION_NEWLINE_CRLF  /* limit */

#define ONIG_OPTION_ON(options,regopt)      ((options) |= (regopt))
#define ONIG_OPTION_OFF(options,regopt)     ((options) &= ~(regopt))
#define ONIG_IS_OPTION_ON(options,option)   ((options) & (option))

/* syntax */
typedef struct {
  unsigned int   op;
  unsigned int   op2;
  unsigned int   behavior;
  OnigOptionType options;   /* default option */
  OnigMetaCharTableType meta_char_table;
} OnigSyntaxType;

ONIG_EXTERN const OnigSyntaxType OnigSyntaxASIS;
ONIG_EXTERN const OnigSyntaxType OnigSyntaxPosixBasic;
ONIG_EXTERN const OnigSyntaxType OnigSyntaxPosixExtended;
ONIG_EXTERN const OnigSyntaxType OnigSyntaxEmacs;
ONIG_EXTERN const OnigSyntaxType OnigSyntaxGrep;
ONIG_EXTERN const OnigSyntaxType OnigSyntaxGnuRegex;
ONIG_EXTERN const OnigSyntaxType OnigSyntaxJava;
ONIG_EXTERN const OnigSyntaxType OnigSyntaxPerl58;
ONIG_EXTERN const OnigSyntaxType OnigSyntaxPerl58_NG;
ONIG_EXTERN const OnigSyntaxType OnigSyntaxPerl;
ONIG_EXTERN const OnigSyntaxType OnigSyntaxRuby;
ONIG_EXTERN const OnigSyntaxType OnigSyntaxPython;

/* predefined syntaxes (see regsyntax.c) */
#define ONIG_SYNTAX_ASIS               (&OnigSyntaxASIS)
#define ONIG_SYNTAX_POSIX_BASIC        (&OnigSyntaxPosixBasic)
#define ONIG_SYNTAX_POSIX_EXTENDED     (&OnigSyntaxPosixExtended)
#define ONIG_SYNTAX_EMACS              (&OnigSyntaxEmacs)
#define ONIG_SYNTAX_GREP               (&OnigSyntaxGrep)
#define ONIG_SYNTAX_GNU_REGEX          (&OnigSyntaxGnuRegex)
#define ONIG_SYNTAX_JAVA               (&OnigSyntaxJava)
#define ONIG_SYNTAX_PERL58             (&OnigSyntaxPerl58)
#define ONIG_SYNTAX_PERL58_NG          (&OnigSyntaxPerl58_NG)
#define ONIG_SYNTAX_PERL               (&OnigSyntaxPerl)
#define ONIG_SYNTAX_RUBY               (&OnigSyntaxRuby)
#define ONIG_SYNTAX_PYTHON             (&OnigSyntaxPython)

/* default syntax */
ONIG_EXTERN const OnigSyntaxType*   OnigDefaultSyntax;
#define ONIG_SYNTAX_DEFAULT   OnigDefaultSyntax

/* syntax (operators) */
#define ONIG_SYN_OP_VARIABLE_META_CHARACTERS    (1U<<0)
#define ONIG_SYN_OP_DOT_ANYCHAR                 (1U<<1)   /* . */
#define ONIG_SYN_OP_ASTERISK_ZERO_INF           (1U<<2)   /* * */
#define ONIG_SYN_OP_ESC_ASTERISK_ZERO_INF       (1U<<3)
#define ONIG_SYN_OP_PLUS_ONE_INF                (1U<<4)   /* + */
#define ONIG_SYN_OP_ESC_PLUS_ONE_INF            (1U<<5)
#define ONIG_SYN_OP_QMARK_ZERO_ONE              (1U<<6)   /* ? */
#define ONIG_SYN_OP_ESC_QMARK_ZERO_ONE          (1U<<7)
#define ONIG_SYN_OP_BRACE_INTERVAL              (1U<<8)   /* {lower,upper} */
#define ONIG_SYN_OP_ESC_BRACE_INTERVAL          (1U<<9)   /* \{lower,upper\} */
#define ONIG_SYN_OP_VBAR_ALT                    (1U<<10)   /* | */
#define ONIG_SYN_OP_ESC_VBAR_ALT                (1U<<11)  /* \| */
#define ONIG_SYN_OP_LPAREN_SUBEXP               (1U<<12)  /* (...)   */
#define ONIG_SYN_OP_ESC_LPAREN_SUBEXP           (1U<<13)  /* \(...\) */
#define ONIG_SYN_OP_ESC_AZ_BUF_ANCHOR           (1U<<14)  /* \A, \Z, \z */
#define ONIG_SYN_OP_ESC_CAPITAL_G_BEGIN_ANCHOR  (1U<<15)  /* \G     */
#define ONIG_SYN_OP_DECIMAL_BACKREF             (1U<<16)  /* \num   */
#define ONIG_SYN_OP_BRACKET_CC                  (1U<<17)  /* [...]  */
#define ONIG_SYN_OP_ESC_W_WORD                  (1U<<18)  /* \w, \W */
#define ONIG_SYN_OP_ESC_LTGT_WORD_BEGIN_END     (1U<<19)  /* \<. \> */
#define ONIG_SYN_OP_ESC_B_WORD_BOUND            (1U<<20)  /* \b, \B */
#define ONIG_SYN_OP_ESC_S_WHITE_SPACE           (1U<<21)  /* \s, \S */
#define ONIG_SYN_OP_ESC_D_DIGIT                 (1U<<22)  /* \d, \D */
#define ONIG_SYN_OP_LINE_ANCHOR                 (1U<<23)  /* ^, $   */
#define ONIG_SYN_OP_POSIX_BRACKET               (1U<<24)  /* [:xxxx:] */
#define ONIG_SYN_OP_QMARK_NON_GREEDY            (1U<<25)  /* ??,*?,+?,{n,m}? */
#define ONIG_SYN_OP_ESC_CONTROL_CHARS           (1U<<26)  /* \n,\r,\t,\a ... */
#define ONIG_SYN_OP_ESC_C_CONTROL               (1U<<27)  /* \cx  */
#define ONIG_SYN_OP_ESC_OCTAL3                  (1U<<28)  /* \OOO */
#define ONIG_SYN_OP_ESC_X_HEX2                  (1U<<29)  /* \xHH */
#define ONIG_SYN_OP_ESC_X_BRACE_HEX8            (1U<<30)  /* \x{7HHHHHHH} */
#define ONIG_SYN_OP_ESC_O_BRACE_OCTAL           (1U<<31)  /* \o{OOO} */

#define ONIG_SYN_OP2_ESC_CAPITAL_Q_QUOTE        (1U<<0)  /* \Q...\E */
#define ONIG_SYN_OP2_QMARK_GROUP_EFFECT         (1U<<1)  /* (?...) */
#define ONIG_SYN_OP2_OPTION_PERL                (1U<<2)  /* (?imsxadlu), (?-imsx), (?^imsxalu) */
#define ONIG_SYN_OP2_OPTION_RUBY                (1U<<3)  /* (?imxadu), (?-imx)  */
#define ONIG_SYN_OP2_PLUS_POSSESSIVE_REPEAT     (1U<<4)  /* ?+,*+,++ */
#define ONIG_SYN_OP2_PLUS_POSSESSIVE_INTERVAL   (1U<<5)  /* {n,m}+   */
#define ONIG_SYN_OP2_CCLASS_SET_OP              (1U<<6)  /* [...&&..[..]..] */
#define ONIG_SYN_OP2_QMARK_LT_NAMED_GROUP       (1U<<7)  /* (?<name>...) */
#define ONIG_SYN_OP2_ESC_K_NAMED_BACKREF        (1U<<8)  /* \k<name> */
#define ONIG_SYN_OP2_ESC_G_SUBEXP_CALL          (1U<<9)  /* \g<name>, \g<n> */
#define ONIG_SYN_OP2_ATMARK_CAPTURE_HISTORY     (1U<<10) /* (?@..),(?@<x>..) */
#define ONIG_SYN_OP2_ESC_CAPITAL_C_BAR_CONTROL  (1U<<11) /* \C-x */
#define ONIG_SYN_OP2_ESC_CAPITAL_M_BAR_META     (1U<<12) /* \M-x */
#define ONIG_SYN_OP2_ESC_V_VTAB                 (1U<<13) /* \v as VTAB */
#define ONIG_SYN_OP2_ESC_U_HEX4                 (1U<<14) /* \uHHHH */
#define ONIG_SYN_OP2_ESC_GNU_BUF_ANCHOR         (1U<<15) /* \`, \' */
#define ONIG_SYN_OP2_ESC_P_BRACE_CHAR_PROPERTY  (1U<<16) /* \p{...}, \P{...} */
#define ONIG_SYN_OP2_ESC_P_BRACE_CIRCUMFLEX_NOT (1U<<17) /* \p{^..}, \P{^..} */
/* #define ONIG_SYN_OP2_CHAR_PROPERTY_PREFIX_IS (1U<<18) */
#define ONIG_SYN_OP2_ESC_H_XDIGIT               (1U<<19) /* \h, \H */
#define ONIG_SYN_OP2_INEFFECTIVE_ESCAPE         (1U<<20) /* \ */
#define ONIG_SYN_OP2_ESC_CAPITAL_R_LINEBREAK    (1U<<21) /* \R as (?>\x0D\x0A|[\x0A-\x0D\x{85}\x{2028}\x{2029}]) */
#define ONIG_SYN_OP2_ESC_CAPITAL_X_EXTENDED_GRAPHEME_CLUSTER (1U<<22) /* \X */
#define ONIG_SYN_OP2_ESC_V_VERTICAL_WHITESPACE   (1U<<23) /* \v, \V -- Perl */ /* NOTIMPL */
#define ONIG_SYN_OP2_ESC_H_HORIZONTAL_WHITESPACE (1U<<24) /* \h, \H -- Perl */ /* NOTIMPL */
#define ONIG_SYN_OP2_ESC_CAPITAL_K_KEEP         (1U<<25) /* \K */
#define ONIG_SYN_OP2_ESC_G_BRACE_BACKREF        (1U<<26) /* \g{name}, \g{n} */
#define ONIG_SYN_OP2_QMARK_SUBEXP_CALL          (1U<<27) /* (?&name), (?n), (?R), (?0) */
#define ONIG_SYN_OP2_QMARK_VBAR_BRANCH_RESET    (1U<<28) /* (?|...) */         /* NOTIMPL */
#define ONIG_SYN_OP2_QMARK_LPAREN_CONDITION     (1U<<29) /* (?(cond)yes...|no...) */
#define ONIG_SYN_OP2_QMARK_CAPITAL_P_NAMED_GROUP (1U<<30) /* (?P<name>...), (?P=name), (?P>name) -- Python/PCRE */
#define ONIG_SYN_OP2_QMARK_TILDE_ABSENT         (1U<<31) /* (?~...) */
/* #define ONIG_SYN_OP2_OPTION_JAVA                (1U<<xx) */ /* (?idmsux), (?-idmsux) */ /* NOTIMPL */

/* syntax (behavior) */
#define ONIG_SYN_CONTEXT_INDEP_ANCHORS           (1U<<31) /* not implemented */
#define ONIG_SYN_CONTEXT_INDEP_REPEAT_OPS        (1U<<0)  /* ?, *, +, {n,m} */
#define ONIG_SYN_CONTEXT_INVALID_REPEAT_OPS      (1U<<1)  /* error or ignore */
#define ONIG_SYN_ALLOW_UNMATCHED_CLOSE_SUBEXP    (1U<<2)  /* ...)... */
#define ONIG_SYN_ALLOW_INVALID_INTERVAL          (1U<<3)  /* {??? */
#define ONIG_SYN_ALLOW_INTERVAL_LOW_ABBREV       (1U<<4)  /* {,n} => {0,n} */
#define ONIG_SYN_STRICT_CHECK_BACKREF            (1U<<5)  /* /(\1)/,/\1()/ ..*/
#define ONIG_SYN_DIFFERENT_LEN_ALT_LOOK_BEHIND   (1U<<6)  /* (?<=a|bc) */
#define ONIG_SYN_CAPTURE_ONLY_NAMED_GROUP        (1U<<7)  /* see doc/RE */
#define ONIG_SYN_ALLOW_MULTIPLEX_DEFINITION_NAME (1U<<8)  /* (?<x>)(?<x>) */
#define ONIG_SYN_FIXED_INTERVAL_IS_GREEDY_ONLY   (1U<<9)  /* a{n}?=(?:a{n})? */
#define ONIG_SYN_ALLOW_MULTIPLEX_DEFINITION_NAME_CALL (1U<<10)  /* (?<x>)(?<x>)(?&x) */
#define ONIG_SYN_USE_LEFT_MOST_NAMED_GROUP       (1U<<11) /* (?<x>)(?<x>)\k<x> */

/* syntax (behavior) in char class [...] */
#define ONIG_SYN_NOT_NEWLINE_IN_NEGATIVE_CC      (1U<<20) /* [^...] */
#define ONIG_SYN_BACKSLASH_ESCAPE_IN_CC          (1U<<21) /* [..\w..] etc.. */
#define ONIG_SYN_ALLOW_EMPTY_RANGE_IN_CC         (1U<<22)
#define ONIG_SYN_ALLOW_DOUBLE_RANGE_OP_IN_CC     (1U<<23) /* [0-9-a]=[0-9\-a] */
/* syntax (behavior) warning */
#define ONIG_SYN_WARN_CC_OP_NOT_ESCAPED          (1U<<24) /* [,-,] */
#define ONIG_SYN_WARN_REDUNDANT_NESTED_REPEAT    (1U<<25) /* (?:a*)+ */
#define ONIG_SYN_WARN_CC_DUP                     (1U<<26) /* [aa] */

/* meta character specifiers (onig_set_meta_char()) */
#define ONIG_META_CHAR_ESCAPE               0
#define ONIG_META_CHAR_ANYCHAR              1
#define ONIG_META_CHAR_ANYTIME              2
#define ONIG_META_CHAR_ZERO_OR_ONE_TIME     3
#define ONIG_META_CHAR_ONE_OR_MORE_TIME     4
#define ONIG_META_CHAR_ANYCHAR_ANYTIME      5

#define ONIG_INEFFECTIVE_META_CHAR          0

/* error codes */
#define ONIG_IS_PATTERN_ERROR(ecode)   ((ecode) <= -100 && (ecode) > -1000)
/* normal return */
#define ONIG_NORMAL                                            0
#define ONIG_MISMATCH                                         -1
#define ONIG_NO_SUPPORT_CONFIG                                -2

/* internal error */
#define ONIGERR_MEMORY                                         -5
#define ONIGERR_TYPE_BUG                                       -6
#define ONIGERR_PARSER_BUG                                    -11
#define ONIGERR_STACK_BUG                                     -12
#define ONIGERR_UNDEFINED_BYTECODE                            -13
#define ONIGERR_UNEXPECTED_BYTECODE                           -14
#define ONIGERR_MATCH_STACK_LIMIT_OVER                        -15
#define ONIGERR_PARSE_DEPTH_LIMIT_OVER                        -16
#define ONIGERR_DEFAULT_ENCODING_IS_NOT_SET                   -21
#define ONIGERR_SPECIFIED_ENCODING_CANT_CONVERT_TO_WIDE_CHAR  -22
/* general error */
#define ONIGERR_INVALID_ARGUMENT                              -30
/* syntax error */
#define ONIGERR_END_PATTERN_AT_LEFT_BRACE                    -100
#define ONIGERR_END_PATTERN_AT_LEFT_BRACKET                  -101
#define ONIGERR_EMPTY_CHAR_CLASS                             -102
#define ONIGERR_PREMATURE_END_OF_CHAR_CLASS                  -103
#define ONIGERR_END_PATTERN_AT_ESCAPE                        -104
#define ONIGERR_END_PATTERN_AT_META                          -105
#define ONIGERR_END_PATTERN_AT_CONTROL                       -106
#define ONIGERR_META_CODE_SYNTAX                             -108
#define ONIGERR_CONTROL_CODE_SYNTAX                          -109
#define ONIGERR_CHAR_CLASS_VALUE_AT_END_OF_RANGE             -110
#define ONIGERR_CHAR_CLASS_VALUE_AT_START_OF_RANGE           -111
#define ONIGERR_UNMATCHED_RANGE_SPECIFIER_IN_CHAR_CLASS      -112
#define ONIGERR_TARGET_OF_REPEAT_OPERATOR_NOT_SPECIFIED      -113
#define ONIGERR_TARGET_OF_REPEAT_OPERATOR_INVALID            -114
#define ONIGERR_NESTED_REPEAT_OPERATOR                       -115
#define ONIGERR_UNMATCHED_CLOSE_PARENTHESIS                  -116
#define ONIGERR_END_PATTERN_WITH_UNMATCHED_PARENTHESIS       -117
#define ONIGERR_END_PATTERN_IN_GROUP                         -118
#define ONIGERR_UNDEFINED_GROUP_OPTION                       -119
#define ONIGERR_INVALID_POSIX_BRACKET_TYPE                   -121
#define ONIGERR_INVALID_LOOK_BEHIND_PATTERN                  -122
#define ONIGERR_INVALID_REPEAT_RANGE_PATTERN                 -123
#define ONIGERR_INVALID_CONDITION_PATTERN                    -124
/* values error (syntax error) */
#define ONIGERR_TOO_BIG_NUMBER                               -200
#define ONIGERR_TOO_BIG_NUMBER_FOR_REPEAT_RANGE              -201
#define ONIGERR_UPPER_SMALLER_THAN_LOWER_IN_REPEAT_RANGE     -202
#define ONIGERR_EMPTY_RANGE_IN_CHAR_CLASS                    -203
#define ONIGERR_MISMATCH_CODE_LENGTH_IN_CLASS_RANGE          -204
#define ONIGERR_TOO_MANY_MULTI_BYTE_RANGES                   -205
#define ONIGERR_TOO_SHORT_MULTI_BYTE_STRING                  -206
#define ONIGERR_TOO_BIG_BACKREF_NUMBER                       -207
#define ONIGERR_INVALID_BACKREF                              -208
#define ONIGERR_NUMBERED_BACKREF_OR_CALL_NOT_ALLOWED         -209
#define ONIGERR_TOO_MANY_CAPTURE_GROUPS                      -210
#define ONIGERR_TOO_SHORT_DIGITS                             -211
#define ONIGERR_TOO_LONG_WIDE_CHAR_VALUE                     -212
#define ONIGERR_EMPTY_GROUP_NAME                             -214
#define ONIGERR_INVALID_GROUP_NAME                           -215
#define ONIGERR_INVALID_CHAR_IN_GROUP_NAME                   -216
#define ONIGERR_UNDEFINED_NAME_REFERENCE                     -217
#define ONIGERR_UNDEFINED_GROUP_REFERENCE                    -218
#define ONIGERR_MULTIPLEX_DEFINED_NAME                       -219
#define ONIGERR_MULTIPLEX_DEFINITION_NAME_CALL               -220
#define ONIGERR_NEVER_ENDING_RECURSION                       -221
#define ONIGERR_GROUP_NUMBER_OVER_FOR_CAPTURE_HISTORY        -222
#define ONIGERR_INVALID_CHAR_PROPERTY_NAME                   -223
#define ONIGERR_INVALID_CODE_POINT_VALUE                     -400
#define ONIGERR_INVALID_WIDE_CHAR_VALUE                      -400
#define ONIGERR_TOO_BIG_WIDE_CHAR_VALUE                      -401
#define ONIGERR_NOT_SUPPORTED_ENCODING_COMBINATION           -402
#define ONIGERR_INVALID_COMBINATION_OF_OPTIONS               -403

/* errors related to thread */
/* #define ONIGERR_OVER_THREAD_PASS_LIMIT_COUNT                -1001 */


/* must be smaller than BIT_STATUS_BITS_NUM (unsigned int * 8) */
#define ONIG_MAX_CAPTURE_HISTORY_GROUP   31
#define ONIG_IS_CAPTURE_HISTORY_GROUP(r, i) \
  ((i) <= ONIG_MAX_CAPTURE_HISTORY_GROUP && (r)->list && (r)->list[i])

#ifdef USE_CAPTURE_HISTORY
typedef struct OnigCaptureTreeNodeStruct {
  int group;   /* group number */
  OnigPosition beg;
  OnigPosition end;
  int allocated;
  int num_childs;
  struct OnigCaptureTreeNodeStruct** childs;
} OnigCaptureTreeNode;
#endif

/* match result region type */
struct re_registers {
  int  allocated;
  int  num_regs;
  OnigPosition* beg;
  OnigPosition* end;
#ifdef USE_CAPTURE_HISTORY
  /* extended */
  OnigCaptureTreeNode* history_root;  /* capture history tree root */
#endif
};

/* capture tree traverse */
#define ONIG_TRAVERSE_CALLBACK_AT_FIRST   1
#define ONIG_TRAVERSE_CALLBACK_AT_LAST    2
#define ONIG_TRAVERSE_CALLBACK_AT_BOTH \
  ( ONIG_TRAVERSE_CALLBACK_AT_FIRST | ONIG_TRAVERSE_CALLBACK_AT_LAST )


#define ONIG_REGION_NOTPOS            -1

typedef struct re_registers   OnigRegion;

typedef struct {
  OnigEncoding enc;
  OnigUChar* par;
  OnigUChar* par_end;
} OnigErrorInfo;

typedef struct {
  int lower;
  int upper;
} OnigRepeatRange;

typedef void (*OnigWarnFunc)(const char* s);
extern void onig_null_warn(const char* s);
#define ONIG_NULL_WARN       onig_null_warn

#define ONIG_CHAR_TABLE_SIZE   256

typedef struct re_pattern_buffer {
  /* common members of BBuf(bytes-buffer) */
  unsigned char* p;         /* compiled pattern */
  unsigned int used;        /* used space for p */
  unsigned int alloc;       /* allocated space for p */

  int num_mem;                   /* used memory(...) num counted from 1 */
  int num_repeat;                /* OP_REPEAT/OP_REPEAT_NG id-counter */
  int num_null_check;            /* OP_NULL_CHECK_START/END id counter */
  int num_comb_exp_check;        /* combination explosion check */
  int num_call;                  /* number of subexp call */
  unsigned int capture_history;  /* (?@...) flag (1-31) */
  unsigned int bt_mem_start;     /* need backtrack flag */
  unsigned int bt_mem_end;       /* need backtrack flag */
  int stack_pop_level;
  int repeat_range_alloc;

  OnigOptionType    options;

  OnigRepeatRange* repeat_range;

  OnigEncoding      enc;
  const OnigSyntaxType* syntax;
  void*             name_table;
  OnigCaseFoldType  case_fold_flag;

  /* optimization info (string search, char-map and anchors) */
  int            optimize;          /* optimize flag */
  int            threshold_len;     /* search str-length for apply optimize */
  int            anchor;            /* BEGIN_BUF, BEGIN_POS, (SEMI_)END_BUF */
  OnigDistance   anchor_dmin;       /* (SEMI_)END_BUF anchor distance */
  OnigDistance   anchor_dmax;       /* (SEMI_)END_BUF anchor distance */
  int            sub_anchor;        /* start-anchor for exact or map */
  unsigned char *exact;
  unsigned char *exact_end;
  unsigned char  map[ONIG_CHAR_TABLE_SIZE]; /* used as BM skip or char-map */
  int           *int_map;                   /* BM skip for exact_len > 255 */
  int           *int_map_backward;          /* BM skip for backward search */
  OnigDistance   dmin;                      /* min-distance of exact or map */
  OnigDistance   dmax;                      /* max-distance of exact or map */

  /* regex_t link chain */
  struct re_pattern_buffer* chain;  /* escape compile-conflict */
} OnigRegexType;

typedef OnigRegexType*  OnigRegex;

#ifndef ONIG_ESCAPE_REGEX_T_COLLISION
typedef OnigRegexType  regex_t;
#endif


typedef struct {
  int             num_of_elements;
  OnigEncoding    pattern_enc;
  OnigEncoding    target_enc;
  const OnigSyntaxType* syntax;
  OnigOptionType  option;
  OnigCaseFoldType   case_fold_flag;
} OnigCompileInfo;

/* Oniguruma Native API */
ONIG_EXTERN
int onig_initialize(OnigEncoding encodings[], int n);
ONIG_EXTERN
int onig_init(void);
ONIG_EXTERN
int onig_error_code_to_str(OnigUChar* s, OnigPosition err_code, ...);
ONIG_EXTERN
void onig_set_warn_func(OnigWarnFunc f);
ONIG_EXTERN
void onig_set_verb_warn_func(OnigWarnFunc f);
ONIG_EXTERN
int onig_new(OnigRegex*, const OnigUChar* pattern, const OnigUChar* pattern_end, OnigOptionType option, OnigEncoding enc, const OnigSyntaxType* syntax, OnigErrorInfo* einfo);
ONIG_EXTERN
int onig_reg_init(OnigRegex reg, OnigOptionType option, OnigCaseFoldType case_fold_flag, OnigEncoding enc, const OnigSyntaxType* syntax);
ONIG_EXTERN
int onig_new_without_alloc(OnigRegex, const OnigUChar* pattern, const OnigUChar* pattern_end, OnigOptionType option, OnigEncoding enc, const OnigSyntaxType* syntax, OnigErrorInfo* einfo);
ONIG_EXTERN
int onig_new_deluxe(OnigRegex* reg, const OnigUChar* pattern, const OnigUChar* pattern_end, OnigCompileInfo* ci, OnigErrorInfo* einfo);
ONIG_EXTERN
void onig_free(OnigRegex);
ONIG_EXTERN
void onig_free_body(OnigRegex);
ONIG_EXTERN
OnigPosition onig_scan(OnigRegex reg, const OnigUChar* str, const OnigUChar* end, OnigRegion* region, OnigOptionType option, int (*scan_callback)(OnigPosition, OnigPosition, OnigRegion*, void*), void* callback_arg);
ONIG_EXTERN
OnigPosition onig_search(OnigRegex, const OnigUChar* str, const OnigUChar* end, const OnigUChar* start, const OnigUChar* range, OnigRegion* region, OnigOptionType option);
ONIG_EXTERN
OnigPosition onig_search_gpos(OnigRegex, const OnigUChar* str, const OnigUChar* end, const OnigUChar* global_pos, const OnigUChar* start, const OnigUChar* range, OnigRegion* region, OnigOptionType option);
ONIG_EXTERN
OnigPosition onig_match(OnigRegex, const OnigUChar* str, const OnigUChar* end, const OnigUChar* at, OnigRegion* region, OnigOptionType option);
ONIG_EXTERN
OnigRegion* onig_region_new(void);
ONIG_EXTERN
void onig_region_init(OnigRegion* region);
ONIG_EXTERN
void onig_region_free(OnigRegion* region, int free_self);
ONIG_EXTERN
void onig_region_copy(OnigRegion* to, const OnigRegion* from);
ONIG_EXTERN
void onig_region_clear(OnigRegion* region);
ONIG_EXTERN
int onig_region_resize(OnigRegion* region, int n);
ONIG_EXTERN
int onig_region_set(OnigRegion* region, int at, int beg, int end);
ONIG_EXTERN
int onig_name_to_group_numbers(OnigRegex reg, const OnigUChar* name, const OnigUChar* name_end, int** nums);
ONIG_EXTERN
int onig_name_to_backref_number(OnigRegex reg, const OnigUChar* name, const OnigUChar* name_end, const OnigRegion *region);
ONIG_EXTERN
int onig_foreach_name(OnigRegex reg, int (*func)(const OnigUChar*, const OnigUChar*,int,int*,OnigRegex,void*), void* arg);
ONIG_EXTERN
int onig_number_of_names(const OnigRegexType *reg);
ONIG_EXTERN
int onig_number_of_captures(const OnigRegexType *reg);
ONIG_EXTERN
int onig_number_of_capture_histories(const OnigRegexType *reg);
#ifdef USE_CAPTURE_HISTORY
ONIG_EXTERN
OnigCaptureTreeNode* onig_get_capture_tree(OnigRegion* region);
#endif
ONIG_EXTERN
int onig_capture_tree_traverse(OnigRegion* region, int at, int(*callback_func)(int,OnigPosition,OnigPosition,int,int,void*), void* arg);
ONIG_EXTERN
int onig_noname_group_capture_is_active(const OnigRegexType *reg);
ONIG_EXTERN
OnigEncoding onig_get_encoding(const OnigRegexType *reg);
ONIG_EXTERN
OnigOptionType onig_get_options(const OnigRegexType *reg);
ONIG_EXTERN
OnigCaseFoldType onig_get_case_fold_flag(const OnigRegexType *reg);
ONIG_EXTERN
const OnigSyntaxType* onig_get_syntax(const OnigRegexType *reg);
ONIG_EXTERN
int onig_set_default_syntax(const OnigSyntaxType* syntax);
ONIG_EXTERN
void onig_copy_syntax(OnigSyntaxType* to, const OnigSyntaxType* from);
ONIG_EXTERN
unsigned int onig_get_syntax_op(const OnigSyntaxType* syntax);
ONIG_EXTERN
unsigned int onig_get_syntax_op2(const OnigSyntaxType* syntax);
ONIG_EXTERN
unsigned int onig_get_syntax_behavior(const OnigSyntaxType* syntax);
ONIG_EXTERN
OnigOptionType onig_get_syntax_options(const OnigSyntaxType* syntax);
ONIG_EXTERN
void onig_set_syntax_op(OnigSyntaxType* syntax, unsigned int op);
ONIG_EXTERN
void onig_set_syntax_op2(OnigSyntaxType* syntax, unsigned int op2);
ONIG_EXTERN
void onig_set_syntax_behavior(OnigSyntaxType* syntax, unsigned int behavior);
ONIG_EXTERN
void onig_set_syntax_options(OnigSyntaxType* syntax, OnigOptionType options);
ONIG_EXTERN
int onig_set_meta_char(OnigSyntaxType* syntax, unsigned int what, OnigCodePoint code);
ONIG_EXTERN
void onig_copy_encoding(OnigEncodingType *to, OnigEncoding from);
ONIG_EXTERN
OnigCaseFoldType onig_get_default_case_fold_flag(void);
ONIG_EXTERN
int onig_set_default_case_fold_flag(OnigCaseFoldType case_fold_flag);
ONIG_EXTERN
unsigned int onig_get_match_stack_limit_size(void);
ONIG_EXTERN
int onig_set_match_stack_limit_size(unsigned int size);
ONIG_EXTERN
unsigned int onig_get_parse_depth_limit(void);
ONIG_EXTERN
int onig_set_parse_depth_limit(unsigned int depth);
ONIG_EXTERN
int onig_end(void);
ONIG_EXTERN
const char* onig_version(void);
ONIG_EXTERN
const char* onig_copyright(void);

RUBY_SYMBOL_EXPORT_END

#ifdef __cplusplus
# if 0
{ /* satisfy cc-mode */
# endif
}
#endif

#endif /* ONIGMO_H */
