package cj_mail.imap

import std.regex.*
import std.collection.*
import cj_mail.exception.*
import std.convert.*

public struct MailboxState <: ToString{
    public var exists: Int64
    public var recent: Int64
    public var flags: ArrayList<String>

    public init(exists: Int64, recent: Int64, flags: ArrayList<String>) {
        this.exists = exists
        this.recent = recent
        this.flags = flags
    }

    public init() {
        this(0, 0, ArrayList<String>())
    }

    public func toString(): String {
        "MailboxState(exists=${exists}, recent=${recent}, flags=${flags})"
    }
}

public func parseMailBoxState(content: String): MailboxState {
    var existsRegex = Regex("\\* (\\d+) EXISTS")
    var exists = match (existsRegex.matcher(content).find()) {
        case Some(s) =>
            Int64.parse(s.matchStr(1))
        case None =>
            0
    }
    var recentRegex = Regex("\\* (\\d+) RECENT")
    var recent = match (recentRegex.matcher(content).find()) {
        case Some(s) =>
            Int64.parse(s.matchStr(1))
        case None =>
            0
    }
    // * FLAGS (\Answered \Flagged \Deleted \Draft \Seen)
    var flagsRegex = Regex("\\* FLAGS \\((.+)\\)")
    var flags = match (flagsRegex.matcher(content).find()) {
        case Some(s) =>
            ArrayList<String>(s.matchStr(1).split(" ", removeEmpty : true))
        case None =>
            ArrayList<String>()
    }
    MailboxState(exists, recent, flags)
}

public enum StoreType <: ToString {
    | SetFlags
    | AddFlags
    | RemoveFlags
    | SetFlagsSilent
    | AddFlagsSilent
    | RemoveFlagsSilent

    public func toString(): String {
        match (this) {
            case SetFlags =>
                "FLAGS"
            case AddFlags =>
                "+FLAGS"
            case RemoveFlags =>
                "-FLAGS"
            case SetFlagsSilent =>
                "FLAGS.SILENT"
            case AddFlagsSilent =>
                "+FLAGS.SILENT"
            case RemoveFlagsSilent =>
                "-FLAGS.SILENT"
        }
    }
}


