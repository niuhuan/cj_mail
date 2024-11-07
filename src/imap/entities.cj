package cj_mail.imap

import cj_lombok.*

@Default
@AllArgsConstructor
@ToString
public struct MailboxState {
    public var exists: Int64
    public var recent: Int64
}
