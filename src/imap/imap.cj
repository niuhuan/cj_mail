package cj_mail.imap

import cj_mail.commons.*
import log.*
import net.tls.*
import std.socket.*
import cj_lombok.*
import std.regex.*
import std.io.*
import std.collection.*

@AllArgsConstructor
@ToString
@Default
public class ImapException <: MailException {
   public var response: String
}


let fetchRegex = Regex("^\\* \\d+ FETCH [\\S\\s]+ \\{(\\d+)\\}$")

public class Imap {

    let logger = getGlobalLogger(("cj_mail", "Imap"))

    public var host: String =  ""
    public var tlsPort: UInt16 = 993

    public var connection: ?MailConnection = None
    
    private var cmdIdx = 0;

    public func nextCmdIdx() {
        cmdIdx += 1
        cmdIdx %= 1000
        if (cmdIdx == 0) {
            cmdIdx = 1
        }
        var str = cmdIdx.toString()
        while (str.size < 3) {
            str = "0" + str
        }
        return "A${str}"
    }

    public func readCommand(cmdIdx: Option<String>): String {
        let reader = this.connection.getOrThrow({=>MailConnectExcption("Not connected")}).reader
        match (cmdIdx) {
            case Some(cmdIdx)=>
                let builder = StringBuilder()
                while(true) {
                    let line = reader.readln().getOrThrow({=>MailConnectExcption("Connect has been eof")})
                    logger.trace("S: ${line}")
                    builder.append(line)
                    builder.append("\r\n")
                    if (line.startsWith("* ")) {
                        if (line.endsWith("}")) {
                             let matcher = fetchRegex.matcher(line);
                             match(matcher.find()) {
                                    case Some(s) =>
                                        let len = Int64.parse(s.matchStr(1))
                                        logger.trace(".. for read Rune * ${len} from server ..")
                                        builder.append(String.fromUtf8(reader.readSize(len)))
                                        let left = reader.readln().getOrThrow({=>MailConnectExcption("Connect has been eof")})
                                        logger.trace(".. line left : ${left} ..")
                                        builder.append(left)
                                        builder.append("\r\n")
                                    case None => ()
                             }
                        }
                    } else if (line.startsWith("${cmdIdx} ")) {
                        if (line.startsWith("${cmdIdx} OK ")) {
                            return builder.toString()
                        } else {
                            throw ImapException(line)
                        }
                    } else {
                        throw MailContentParseException("Invalid response : ${line}");
                    }
                }
                throw Exception("Unreachable")
            case None=>
                    let line = reader.readln().getOrThrow({=>MailConnectExcption("Connect has been eof")})
                    logger.trace("S: ${line}")
                    return line
        }
    }

   public func writeCommand(command: String) {
        let writer = this.connection.getOrThrow({=>MailConnectExcption("Not connected")})
        logger.trace("C: ${command}")
        writer.write(command)
        writer.write("\r\n")
        writer.flush()
    }

    public func connect() {
      this.connection = defaultTlsConnect(host, tlsPort)
      readCommand(None) // Server Hello
    }

    public func connect(socket: StreamingSocket) {
        this.connection = mailConnection(socket)
        readCommand(None) // Server Hello
    }

    public func login(username: String, password: String) {
        let idx = nextCmdIdx();
        writeCommand("${idx} LOGIN ${username} ${password}")
        readCommand(idx)
    }

    public func select(mailbox: String): MailboxState {
        let idx = nextCmdIdx();
        writeCommand("${idx} SELECT \"${mailbox}\"")
        parseMailBoxState(readCommand(idx))
    }

    public func examine(mailbox: String): MailboxState {
        let idx = nextCmdIdx();
        writeCommand("${idx} EXAMINE ${mailbox}")
        parseMailBoxState(readCommand(idx))
    }

    private func parseMailBoxState(content: String): MailboxState {
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
        MailboxState(exists, recent)
    }

    public func search(criteria: String): ArrayList<Int64> {
        let idx = nextCmdIdx();
        var command = "${idx} SEARCH \"${escapingDoubleQuote(criteria)}\""
        writeCommand(command)
        let result = ArrayList<Int64>();
        for(line in  readCommand(idx).split("\r\n")) {
            if (line.startsWith("* SEARCH ")) {
                for (str in line.split(" ")[2..]) {
                    if (str != "*") {
                        result.append(Int64.parse(str))
                    }
                }
            }
        }
        result
    }

    public func fetch(sequenceSet: Option<String>, dataItems: String, withUid: Bool): (String, String) {
        let idx = nextCmdIdx()
        let sequenceSetValue = match (sequenceSet) {
            case Some(value) => value
            case _ => "1:*" 
        }
        let uidStr = if (withUid) {
            "UID "
        } else {
            ""
        }
        let command = "${idx} ${uidStr}FETCH ${sequenceSetValue} ${dataItems}"
        writeCommand(command)
        (idx, readCommand(idx))
    }

    public func quit() {
        let idx = nextCmdIdx();
        writeCommand("${idx} LOGOUT")
        readCommand(idx)
    }

    public func disconnect() {
        this.connection.getOrThrow().disconnect()
    }

    public func fetchParse(sequenceSet: Option<String>, withUid: Bool): ArrayList<ImapReceiveMail> {
        let mails = ArrayList<(Int64, ReceiveMail)>()
        let (idx, response) = fetch(sequenceSet, "(UID FLAGS INTERNALDATE RFC822.SIZE ENVELOPE BODY BODY[TEXT])", withUid)
        parseImapMailResponses(idx, response, skipHeaders: true)
    }

    public func fetchParse(sequenceSet: Option<String>): ArrayList<ImapReceiveMail> {
        fetchParse(sequenceSet, false)
    }

    public func fetchParse(): ArrayList<ImapReceiveMail> {
        fetchParse(None)
    }

    public func fetchInfo(sequenceSet: Option<String>, withUid: Bool): ArrayList<ImapReceiveMail> {
        let (idx, response) = fetch(
            sequenceSet, 
            "(UID RFC822.SIZE FLAGS BODY.PEEK[HEADER.FIELDS (From To Cc Bcc Subject Date Message-ID Content-Type)])",
            withUid
        )
        parseImapMailResponses(idx, response)
    }

    public func fetchInfo(sequenceSet: Option<String>): ArrayList<ImapReceiveMail> {
        fetchInfo(sequenceSet, false)
    }

    public func fetchInfo(): ArrayList<ImapReceiveMail> {
        fetchInfo(None)
    }

    public func list(referenceName: String, mailboxName: String): String {
        let idx = nextCmdIdx();
        writeCommand("${idx} LIST \"${escapingDoubleQuote(referenceName)}\" \"${escapingDoubleQuote(mailboxName)}\"")
        readCommand(idx)
    }

    private func escapingDoubleQuote(str: String): String {
        str.replace("\"", "\\\"")
    }

}

private func parseImapMailResponses(idx: String, response: String, skipHeaders!: Bool = false): ArrayList<ImapReceiveMail> {
        let reader = StreamReader(ByteArrayStream.fromString(response))
        let mails = ArrayList<ImapReceiveMail>()
        while(true) {
            let line = reader.readln().getOrThrow({=>MailContentParseException()})
            if (line.startsWith("* ")) {
                mails.append(parseImapMail(line, reader, skipHeaders: skipHeaders))
            } else if (line.startsWith("${idx} ")) {
                break
            } else {
                throw MailContentParseException(
                    "not match email", line
                )
            }
        }
        mails
}

private func parseImapMail(line: String, reader: StreamReader, skipHeaders!: Bool = false): ImapReceiveMail {
    var lineReader = StreamReader(ByteArrayStream.fromString(line.trimAscii()))
    let mail = ImapReceiveMail()
    if (lineReader.readRune().getOrThrow({=>MailContentParseException()}) != r"*") {
        throw MailContentParseException()
    }
    if (lineReader.readRune().getOrThrow({=>MailContentParseException()}) != r" ") {
        throw MailContentParseException()
    }
    let (idx, endListByIdx) = imapReaderNumber(lineReader)
    if (endListByIdx) {
        throw MailContentParseException()
    }
    mail.idx = idx
    var imapSetContentType = ""
    var imapSetContentTransferEncoding = ""
    matchRunes("FETCH (", lineReader)
    while (true) {
        let name = imapReadItemName(lineReader)
        if (name == ")") {
            break
        } else if (name == "UID") {
            let (uid, endList) = imapReaderNumber(lineReader)
            mail.uid = uid
            if (endList) {
                break
            }
        } else if (name == "RFC822.SIZE") {
            let (size, endListBySize) = imapReaderNumber(lineReader)
            mail.size = size
            if (endListBySize) {
                break
            }
        } else if (name == "FLAGS") {
            mail.flags = imapReaderFlags(lineReader)
        } else if (name == "INTERNALDATE") {
            // todo
            let _ = lineReader.readRune() // skip \"
            let _ = lineReader.readUntil({rune => rune == r'\"'}).getOrThrow().trimRight("\"")
            // internalDate = time
        } else if (name == "ENVELOPE") {
            // todo
            var subject = ""
            var from = MailAddress()
            var to = ArrayList<MailAddress>()
            let enevelope = match (parseThisItem(lineReader)) {
                case ImapValue.LIST(list) =>
                    list
                case _ =>
                    throw MailContentParseException("Invalid fetch ENVELOPE")
            }
            if (enevelope.size < 7) {
                throw MailContentParseException("Invalid fetch ENVELOPE")
            }
            subject = match (enevelope[1]) {
                case ImapValue.STRING(str) =>
                    str
                case _ =>
                    "" // NIL
            }
            match (enevelope[2]) {
                case ImapValue.LIST(list) =>
                    if (list.size > 0) {
                        match (list[0]) {
                            case ImapValue.LIST(list) =>
                                from = parseImapAddress(list)
                            case _ =>
                                ()
                        }
                    }
                case _ =>  ()
            }
            match (enevelope[5]) {
                case ImapValue.LIST(list) =>
                    for (item in list) {
                        match (item) {
                            case ImapValue.LIST(list) =>
                                to.append(parseImapAddress(list))
                            case _ =>
                                ()
                        }
                    }
                case _ => ()
            }
            if (subject != "") {
                mail.subject = subject
            }
            if (from.address != "" || from.name != "") {
                mail.from = from
            }
            if (!to.isEmpty()) {
                mail.to = to
            }
        } else if (name == "BODY" || name == "BODYSTRUCTURE") {
            // body must be list
            let body = match (parseThisItem(lineReader)) {
                case ImapValue.LIST(list) =>
                    list
                case _ =>
                    throw MailContentParseException("Invalid fetch BODY")
            }
            //
            if (body.size < 1) {
                throw MailContentParseException("Invalid fetch BODY (size < 1)")
            }
            match (body.get(0).getOrThrow()) {
                case ImapValue.STRING(value0) =>
                    if (body.size < 6) {
                        throw MailContentParseException("Invalid fetch BODY (size < 6)")
                    }
                    imapSetContentType = match (body.get(1).getOrThrow()) {
                        case ImapValue.STRING(value1) => "${value0}/${value1}"
                        case _ => value0
                    }
                    imapSetContentTransferEncoding = match (body.get(5).getOrThrow()) {
                        case ImapValue.STRING(value5) => value5
                        case _ => ""
                    }
                case ImapValue.LIST(_) => 
                     match (body.get(body.size - 1).getOrThrow()) {
                        case ImapValue.STRING(last) => 
                            imapSetContentType = "multipart/${last.toAsciiLower()}"
                        case _ => ()
                     }
                case _ => ()
            }
        } else if (name.startsWith("BODY[")) {
            let byteCount = imapReaderByteCount(lineReader);
            if (lineReader.readRune().isSome()) {
                throw MailContentParseException()
            }
            let mailData = reader.readSize(byteCount)
            let str = String.fromUtf8(mailData)
            let (from, to, cc, bcc, subject, data) = parseMailContent(
                str,
                imapSetContentType: imapSetContentType,
                imapSetContentTransferEncoding: imapSetContentTransferEncoding,
                skipHeaders: skipHeaders
            )
            if (from != "") {
                mail.from = parseMailAddress(from)
            }
            if (to != "") {
                mail.to = parseMailAddresses(to)
            }
            if (cc != "") {
                mail.cc = parseMailAddresses(cc)
            }
            if (bcc != "") {
                mail.bcc = parseMailAddresses(bcc)
            }
            mail.subject = subject
            mail.data = data
            lineReader = StreamReader(ByteArrayStream.fromString(reader.readln().getOrThrow({=>MailConnectExcption()})))
        } else {
            throw MailContentParseException(
                "not match imap item name",
                name
            )
        }
    }
    mail
}

private func imapReaderNumber(reader: StreamReader): (Int64, Bool) {
    var endList = false
    let builder = StringBuilder()
    while(true) {
        let rune = reader.readRune().getOrThrow({=>MailConnectExcption("Connect has been eof")})
        if (rune >= r'0' && rune <= r'9') {
            builder.append(rune)
            continue
        } else if (rune == r' ') {
            if (builder.size == 0) {
               continue
            }
            break
        } else if (rune == r')') {
            endList = true
            break
        } else {
            throw MailContentParseException("Invalid NUMBER : ${rune}")
        }
    }
    return (Int64.parse(builder.toString()), endList)
}

private func matchRunes(runes: String, reader: StreamReader) {
    for(rune in runes.runes()) {
        if (rune != reader.readRune().getOrThrow({=>MailConnectExcption()})) {
            throw MailConnectExcption()
        }
    }
}

private func imapReadItemName(reader: StreamReader): String {
    let builder = StringBuilder()
    var inSquareBrackets = false
    while (true) {
        let rune = reader.readRune().getOrThrow({=>MailConnectExcption()})
        if (rune == r" " && !inSquareBrackets) {
            if (builder.size == 0) {
                continue
            }
            break
        } 
        if (!inSquareBrackets) {
            if (rune == r")") {
                if (builder.size == 0) {
                    return ")"
                }
                throw MailContentParseException(" ${builder} ${rune}")
            }
            if (rune == r"(") {
                throw MailContentParseException(" ${builder} ${rune}")
            }
        }
        builder.append(rune)
        if (rune == r"[") {
            inSquareBrackets = true
        } else if (rune == r"]") {
            inSquareBrackets = false
        }  
    }
    builder.toString()
}

public func imapReaderFlags(reader: StreamReader): ArrayList<String> {
    var builder = StringBuilder()
    let list = ArrayList<String>()
    func takeFlag() {
        if (builder.size > 0) {
            list.append(builder.toString())
            builder = StringBuilder()
        }
    }
    var inBrackets = false
    while (true) {
        let rune = reader.readRune().getOrThrow({=>MailConnectExcption()})
        if (rune == r"(") {
            if (!inBrackets) {
                inBrackets = true
            } else {
                throw MailConnectExcption()
            }
        } else if (rune == r")") {
            if (inBrackets) {
                takeFlag()
                break
            } else {
                throw MailConnectExcption()
            }
        } else if (rune == r" ") {
            takeFlag()
        }
    }
    list
}

private func imapReaderByteCount(reader: StreamReader): Int64{
    let builder = StringBuilder()
    var inCurlyBraces = false
    while(true) {
        let rune = reader.readRune().getOrThrow({=>MailContentParseException()})
        if (rune == r" " && !inCurlyBraces) {
            continue
        } 
        if (rune == r"{" && !inCurlyBraces) {
            inCurlyBraces = true
            continue
        }
        if (!inCurlyBraces) {
            throw MailConnectExcption()
        }
        if (rune == r"}") {
            break
        }
        builder.append(rune)
    }
    Int64.parse(builder.toString())
}
