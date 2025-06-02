# frozen_string_literal: true

module Net
  class IMAP < Protocol

    # Net::IMAP::ContinuationRequest represents command continuation requests.
    #
    # The command continuation request response is indicated by a "+" token
    # instead of a tag.  This form of response indicates that the server is
    # ready to accept the continuation of a command from the client.  The
    # remainder of this response is a line of text.
    #
    #   continue_req    ::= "+" SPACE (resp_text / base64)
    #
    # ==== Fields:
    #
    # data:: Returns the data (Net::IMAP::ResponseText).
    #
    # raw_data:: Returns the raw data string.
    class ContinuationRequest < Struct.new(:data, :raw_data)
    end

    # Net::IMAP::UntaggedResponse represents untagged responses.
    #
    # Data transmitted by the server to the client and status responses
    # that do not indicate command completion are prefixed with the token
    # "*", and are called untagged responses.
    #
    #   response_data   ::= "*" SPACE (resp_cond_state / resp_cond_bye /
    #                       mailbox_data / message_data / capability_data)
    #
    # ==== Fields:
    #
    # name:: Returns the name, such as "FLAGS", "LIST", or "FETCH".
    #
    # data:: Returns the data such as an array of flag symbols,
    #        a ((<Net::IMAP::MailboxList>)) object.
    #
    # raw_data:: Returns the raw data string.
    class UntaggedResponse < Struct.new(:name, :data, :raw_data)
    end

    # Net::IMAP::IgnoredResponse represents intentionally ignored responses.
    #
    # This includes untagged response "NOOP" sent by eg. Zimbra to avoid some
    # clients to close the connection.
    #
    # It matches no IMAP standard.
    #
    # ==== Fields:
    #
    # raw_data:: Returns the raw data string.
    class IgnoredResponse < Struct.new(:raw_data)
    end

    # Net::IMAP::TaggedResponse represents tagged responses.
    #
    # The server completion result response indicates the success or
    # failure of the operation.  It is tagged with the same tag as the
    # client command which began the operation.
    #
    #   response_tagged ::= tag SPACE resp_cond_state CRLF
    #
    #   tag             ::= 1*<any ATOM_CHAR except "+">
    #
    #   resp_cond_state ::= ("OK" / "NO" / "BAD") SPACE resp_text
    #
    # ==== Fields:
    #
    # tag:: Returns the tag.
    #
    # name:: Returns the name, one of "OK", "NO", or "BAD".
    #
    # data:: Returns the data. See ((<Net::IMAP::ResponseText>)).
    #
    # raw_data:: Returns the raw data string.
    #
    class TaggedResponse < Struct.new(:tag, :name, :data, :raw_data)
    end

    # Net::IMAP::ResponseText represents texts of responses.
    # The text may be prefixed by the response code.
    #
    #   resp_text       ::= ["[" resp-text-code "]" SP] text
    #
    # ==== Fields:
    #
    # code:: Returns the response code. See ((<Net::IMAP::ResponseCode>)).
    #
    # text:: Returns the text.
    #
    class ResponseText < Struct.new(:code, :text)
    end

    # Net::IMAP::ResponseCode represents response codes.
    #
    #   resp_text_code  ::= "ALERT" /
    #                       "BADCHARSET" [SP "(" astring *(SP astring) ")" ] /
    #                       capability_data / "PARSE" /
    #                       "PERMANENTFLAGS" SP "("
    #                       [flag_perm *(SP flag_perm)] ")" /
    #                       "READ-ONLY" / "READ-WRITE" / "TRYCREATE" /
    #                       "UIDNEXT" SP nz_number / "UIDVALIDITY" SP nz_number /
    #                       "UNSEEN" SP nz_number /
    #                       atom [SP 1*<any TEXT-CHAR except "]">]
    #
    # ==== Fields:
    #
    # name:: Returns the name, such as "ALERT", "PERMANENTFLAGS", or "UIDVALIDITY".
    #
    # data:: Returns the data, if it exists.
    #
    class ResponseCode < Struct.new(:name, :data)
    end

    # Net::IMAP::MailboxList represents contents of the LIST response.
    #
    #   mailbox_list    ::= "(" #("\Marked" / "\Noinferiors" /
    #                       "\Noselect" / "\Unmarked" / flag_extension) ")"
    #                       SPACE (<"> QUOTED_CHAR <"> / nil) SPACE mailbox
    #
    # ==== Fields:
    #
    # attr:: Returns the name attributes. Each name attribute is a symbol
    #        capitalized by String#capitalize, such as :Noselect (not :NoSelect).
    #
    # delim:: Returns the hierarchy delimiter.
    #
    # name:: Returns the mailbox name.
    #
    class MailboxList < Struct.new(:attr, :delim, :name)
    end

    # Net::IMAP::MailboxQuota represents contents of GETQUOTA response.
    # This object can also be a response to GETQUOTAROOT.  In the syntax
    # specification below, the delimiter used with the "#" construct is a
    # single space (SPACE).
    #
    #    quota_list      ::= "(" #quota_resource ")"
    #
    #    quota_resource  ::= atom SPACE number SPACE number
    #
    #    quota_response  ::= "QUOTA" SPACE astring SPACE quota_list
    #
    # ==== Fields:
    #
    # mailbox:: The mailbox with the associated quota.
    #
    # usage:: Current storage usage of the mailbox.
    #
    # quota:: Quota limit imposed on the mailbox.
    #
    class MailboxQuota < Struct.new(:mailbox, :usage, :quota)
    end

    # Net::IMAP::MailboxQuotaRoot represents part of the GETQUOTAROOT
    # response. (GETQUOTAROOT can also return Net::IMAP::MailboxQuota.)
    #
    #    quotaroot_response ::= "QUOTAROOT" SPACE astring *(SPACE astring)
    #
    # ==== Fields:
    #
    # mailbox:: The mailbox with the associated quota.
    #
    # quotaroots:: Zero or more quotaroots that affect the quota on the
    #              specified mailbox.
    #
    class MailboxQuotaRoot < Struct.new(:mailbox, :quotaroots)
    end

    # Net::IMAP::MailboxACLItem represents the response from GETACL.
    #
    #    acl_data        ::= "ACL" SPACE mailbox *(SPACE identifier SPACE rights)
    #
    #    identifier      ::= astring
    #
    #    rights          ::= astring
    #
    # ==== Fields:
    #
    # user:: Login name that has certain rights to the mailbox
    #        that was specified with the getacl command.
    #
    # rights:: The access rights the indicated user has to the
    #          mailbox.
    #
    class MailboxACLItem < Struct.new(:user, :rights, :mailbox)
    end

    # Net::IMAP::Namespace represents a single [RFC-2342] namespace.
    #
    #    Namespace = nil / "(" 1*( "(" string SP  (<"> QUOTED_CHAR <"> /
    #       nil) *(Namespace_Response_Extension) ")" ) ")"
    #
    #    Namespace_Response_Extension = SP string SP "(" string *(SP string)
    #       ")"
    #
    # ==== Fields:
    #
    # prefix:: Returns the namespace prefix string.
    # delim:: Returns nil or the hierarchy delimiter character.
    # extensions:: Returns a hash of extension names to extension flag arrays.
    #
    class Namespace < Struct.new(:prefix, :delim, :extensions)
    end

    # Net::IMAP::Namespaces represents the response from [RFC-2342] NAMESPACE.
    #
    #    Namespace_Response = "*" SP "NAMESPACE" SP Namespace SP Namespace SP
    #       Namespace
    #
    #       ; The first Namespace is the Personal Namespace(s)
    #       ; The second Namespace is the Other Users' Namespace(s)
    #       ; The third Namespace is the Shared Namespace(s)
    #
    # ==== Fields:
    #
    # personal:: Returns an array of Personal Net::IMAP::Namespace objects.
    # other:: Returns an array of Other Users' Net::IMAP::Namespace objects.
    # shared:: Returns an array of Shared Net::IMAP::Namespace objects.
    #
    class Namespaces < Struct.new(:personal, :other, :shared)
    end

    # Net::IMAP::StatusData represents the contents of the STATUS response.
    #
    # ==== Fields:
    #
    # mailbox:: Returns the mailbox name.
    #
    # attr:: Returns a hash. Each key is one of "MESSAGES", "RECENT", "UIDNEXT",
    #        "UIDVALIDITY", "UNSEEN". Each value is a number.
    #
    class StatusData < Struct.new(:mailbox, :attr)
    end

    # Net::IMAP::FetchData represents the contents of the FETCH response.
    #
    # ==== Fields:
    #
    # seqno:: Returns the message sequence number.
    #         (Note: not the unique identifier, even for the UID command response.)
    #
    # attr:: Returns a hash. Each key is a data item name, and each value is
    #        its value.
    #
    #        The current data items are:
    #
    #        [BODY]
    #           A form of BODYSTRUCTURE without extension data.
    #        [BODY[<section>]<<origin_octet>>]
    #           A string expressing the body contents of the specified section.
    #        [BODYSTRUCTURE]
    #           An object that describes the [MIME-IMB] body structure of a message.
    #           See Net::IMAP::BodyTypeBasic, Net::IMAP::BodyTypeText,
    #           Net::IMAP::BodyTypeMessage, Net::IMAP::BodyTypeMultipart.
    #        [ENVELOPE]
    #           A Net::IMAP::Envelope object that describes the envelope
    #           structure of a message.
    #        [FLAGS]
    #           A array of flag symbols that are set for this message. Flag symbols
    #           are capitalized by String#capitalize.
    #        [INTERNALDATE]
    #           A string representing the internal date of the message.
    #        [RFC822]
    #           Equivalent to +BODY[]+.
    #        [RFC822.HEADER]
    #           Equivalent to +BODY.PEEK[HEADER]+.
    #        [RFC822.SIZE]
    #           A number expressing the [RFC-822] size of the message.
    #        [RFC822.TEXT]
    #           Equivalent to +BODY[TEXT]+.
    #        [UID]
    #           A number expressing the unique identifier of the message.
    #
    class FetchData < Struct.new(:seqno, :attr)
    end

    # Net::IMAP::Envelope represents envelope structures of messages.
    #
    # ==== Fields:
    #
    # date:: Returns a string that represents the date.
    #
    # subject:: Returns a string that represents the subject.
    #
    # from:: Returns an array of Net::IMAP::Address that represents the from.
    #
    # sender:: Returns an array of Net::IMAP::Address that represents the sender.
    #
    # reply_to:: Returns an array of Net::IMAP::Address that represents the reply-to.
    #
    # to:: Returns an array of Net::IMAP::Address that represents the to.
    #
    # cc:: Returns an array of Net::IMAP::Address that represents the cc.
    #
    # bcc:: Returns an array of Net::IMAP::Address that represents the bcc.
    #
    # in_reply_to:: Returns a string that represents the in-reply-to.
    #
    # message_id:: Returns a string that represents the message-id.
    #
    class Envelope < Struct.new(:date, :subject, :from, :sender, :reply_to,
                                :to, :cc, :bcc, :in_reply_to, :message_id)
    end

    #
    # Net::IMAP::Address represents electronic mail addresses.
    #
    # ==== Fields:
    #
    # name:: Returns the phrase from [RFC-822] mailbox.
    #
    # route:: Returns the route from [RFC-822] route-addr.
    #
    # mailbox:: nil indicates end of [RFC-822] group.
    #           If non-nil and host is nil, returns [RFC-822] group name.
    #           Otherwise, returns [RFC-822] local-part.
    #
    # host:: nil indicates [RFC-822] group syntax.
    #        Otherwise, returns [RFC-822] domain name.
    #
    class Address < Struct.new(:name, :route, :mailbox, :host)
    end

    #
    # Net::IMAP::ContentDisposition represents Content-Disposition fields.
    #
    # ==== Fields:
    #
    # dsp_type:: Returns the disposition type.
    #
    # param:: Returns a hash that represents parameters of the Content-Disposition
    #         field.
    #
    class ContentDisposition < Struct.new(:dsp_type, :param)
    end

    # Net::IMAP::ThreadMember represents a thread-node returned
    # by Net::IMAP#thread.
    #
    # ==== Fields:
    #
    # seqno:: The sequence number of this message.
    #
    # children:: An array of Net::IMAP::ThreadMember objects for mail
    #            items that are children of this in the thread.
    #
    class ThreadMember < Struct.new(:seqno, :children)
    end

    # Net::IMAP::BodyTypeBasic represents basic body structures of messages.
    #
    # ==== Fields:
    #
    # media_type:: Returns the content media type name as defined in [MIME-IMB].
    #
    # subtype:: Returns the content subtype name as defined in [MIME-IMB].
    #
    # param:: Returns a hash that represents parameters as defined in [MIME-IMB].
    #
    # content_id:: Returns a string giving the content id as defined in [MIME-IMB].
    #
    # description:: Returns a string giving the content description as defined in
    #               [MIME-IMB].
    #
    # encoding:: Returns a string giving the content transfer encoding as defined in
    #            [MIME-IMB].
    #
    # size:: Returns a number giving the size of the body in octets.
    #
    # md5:: Returns a string giving the body MD5 value as defined in [MD5].
    #
    # disposition:: Returns a Net::IMAP::ContentDisposition object giving
    #               the content disposition.
    #
    # language:: Returns a string or an array of strings giving the body
    #            language value as defined in [LANGUAGE-TAGS].
    #
    # extension:: Returns extension data.
    #
    # multipart?:: Returns false.
    #
    class BodyTypeBasic < Struct.new(:media_type, :subtype,
                                     :param, :content_id,
                                     :description, :encoding, :size,
                                     :md5, :disposition, :language,
                                     :extension)
      def multipart?
        return false
      end

      # Obsolete: use +subtype+ instead.  Calling this will
      # generate a warning message to +stderr+, then return
      # the value of +subtype+.
      def media_subtype
        warn("media_subtype is obsolete, use subtype instead.\n", uplevel: 1)
        return subtype
      end
    end

    # Net::IMAP::BodyTypeText represents TEXT body structures of messages.
    #
    # ==== Fields:
    #
    # lines:: Returns the size of the body in text lines.
    #
    # And Net::IMAP::BodyTypeText has all fields of Net::IMAP::BodyTypeBasic.
    #
    class BodyTypeText < Struct.new(:media_type, :subtype,
                                    :param, :content_id,
                                    :description, :encoding, :size,
                                    :lines,
                                    :md5, :disposition, :language,
                                    :extension)
      def multipart?
        return false
      end

      # Obsolete: use +subtype+ instead.  Calling this will
      # generate a warning message to +stderr+, then return
      # the value of +subtype+.
      def media_subtype
        warn("media_subtype is obsolete, use subtype instead.\n", uplevel: 1)
        return subtype
      end
    end

    # Net::IMAP::BodyTypeMessage represents MESSAGE/RFC822 body structures of messages.
    #
    # ==== Fields:
    #
    # envelope:: Returns a Net::IMAP::Envelope giving the envelope structure.
    #
    # body:: Returns an object giving the body structure.
    #
    # And Net::IMAP::BodyTypeMessage has all methods of Net::IMAP::BodyTypeText.
    #
    class BodyTypeMessage < Struct.new(:media_type, :subtype,
                                       :param, :content_id,
                                       :description, :encoding, :size,
                                       :envelope, :body, :lines,
                                       :md5, :disposition, :language,
                                       :extension)
      def multipart?
        return false
      end

      # Obsolete: use +subtype+ instead.  Calling this will
      # generate a warning message to +stderr+, then return
      # the value of +subtype+.
      def media_subtype
        warn("media_subtype is obsolete, use subtype instead.\n", uplevel: 1)
        return subtype
      end
    end

    # Net::IMAP::BodyTypeAttachment represents attachment body structures
    # of messages.
    #
    # ==== Fields:
    #
    # media_type:: Returns the content media type name.
    #
    # subtype:: Returns +nil+.
    #
    # param:: Returns a hash that represents parameters.
    #
    # multipart?:: Returns false.
    #
    class BodyTypeAttachment < Struct.new(:media_type, :subtype,
                                          :param)
      def multipart?
        return false
      end
    end

    # Net::IMAP::BodyTypeMultipart represents multipart body structures
    # of messages.
    #
    # ==== Fields:
    #
    # media_type:: Returns the content media type name as defined in [MIME-IMB].
    #
    # subtype:: Returns the content subtype name as defined in [MIME-IMB].
    #
    # parts:: Returns multiple parts.
    #
    # param:: Returns a hash that represents parameters as defined in [MIME-IMB].
    #
    # disposition:: Returns a Net::IMAP::ContentDisposition object giving
    #               the content disposition.
    #
    # language:: Returns a string or an array of strings giving the body
    #            language value as defined in [LANGUAGE-TAGS].
    #
    # extension:: Returns extension data.
    #
    # multipart?:: Returns true.
    #
    class BodyTypeMultipart < Struct.new(:media_type, :subtype,
                                         :parts,
                                         :param, :disposition, :language,
                                         :extension)
      def multipart?
        return true
      end

      # Obsolete: use +subtype+ instead.  Calling this will
      # generate a warning message to +stderr+, then return
      # the value of +subtype+.
      def media_subtype
        warn("media_subtype is obsolete, use subtype instead.\n", uplevel: 1)
        return subtype
      end
    end

    class BodyTypeExtension < Struct.new(:media_type, :subtype,
                                         :params, :content_id,
                                         :description, :encoding, :size)
      def multipart?
        return false
      end
    end

  end
end
