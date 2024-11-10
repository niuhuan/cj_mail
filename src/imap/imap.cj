package cj_mail.imap

import cj_mail.commons.*
import log.*
import net.tls.*
import std.socket.*
import cj_lombok.*
import std.regex.*
import std.io.*
import std.collection.*
import std.fs.*

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
                        throw MailContentParseException();
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

    public func fetch(sequenceSet: String, dataItems: String) {
        let idx = nextCmdIdx();
        var command = "${idx} FETCH ${sequenceSet} ${dataItems}"
        writeCommand(command)
        readCommand(idx)
    }

    public func quit() {
        let idx = nextCmdIdx();
        writeCommand("${idx} LOGOUT")
        readCommand(idx)
    }

    public func disconnect() {
        this.connection.getOrThrow().disconnect()
    }

    public func fetchParse(sequenceSet: String): ArrayList<(Int64, ReceiveMail)> {
        let emails = ArrayList<(Int64, ReceiveMail)>()
        let content = fetch(sequenceSet, "(FLAGS INTERNALDATE RFC822.SIZE ENVELOPE BODY BODY[TEXT])")
        let reader = StreamReader(ByteArrayStream.fromString(content))
        while (let Some(line) <- reader.readln()) {
            if (line.startsWith("* ")) {
                var builder = StringBuilder(line)
                let matcher = fetchRegex.matcher(line);
                match(matcher.find()) {
                    case Some(s) =>
                        let len = Int64.parse(s.matchStr(1))
                        logger.trace(".. for read Rune * ${len} from context ..")
                        builder.append(String.fromUtf8(reader.readSize(len)))
                        let line = reader.readln().getOrThrow({=>MailConnectExcption("Connect has been eof")})
                        logger.trace(".. line left : ${line} ..")
                        builder.append(line)
                    case None => ()
                }
                var line = builder.toString()
                // parse mail
                var uid = 0
                var flags = ArrayList<String>()
                var internalDate = ""
                var body: Option<ImapValue> = None
                var bodyContext: MailContent = ""
                var size = 0
                var subject = ""
                var from = MailAddress("", "")
                var to = ArrayList<MailAddress>()
                let reader = StreamReader(ByteArrayStream.fromString(line))
                let _ = reader.readUntil({rune => rune == r' '}) // skip "* "
                uid = Int64.parse(reader.readUntil({rune => rune == r' '}).getOrThrow().trimAscii())
                let _ = reader.readUntil({rune => rune == r' '}) // skip "FETCH "
                if (r'(' != reader.readRune().getOrThrow({=>MailConnectExcption("Connect has been eof")})) {
                    throw MailContentParseException("Invalid response")
                }
                while(let Some(dataType) <- reader.readUntil({rune => rune == r' '})) {
                    if (dataType.startsWith(")") || dataType.startsWith(") ")) {
                        break
                    } else if (dataType == " ") {
                        continue
                    } else if (dataType == "FLAGS ") {
                        if (r'(' != reader.readRune().getOrThrow({=>MailConnectExcption("Connect has been eof")})) {
                            throw MailContentParseException("Invalid response")
                        }
                        flags.appendAll(reader.readUntil({rune => rune == r')'}).getOrThrow().trimRight(")").split(" "))
                    } else if (dataType == "INTERNALDATE ") {
                        reader.readRune() // skip \"
                        let time = reader.readUntil({rune => rune == r'\"'}).getOrThrow().trimRight("\"")
                        internalDate = time
                    } else if (dataType == "RFC822.SIZE ") {
                        size = Int64.parse(reader.readUntil({rune => rune == r' '}).getOrThrow().trimAscii())
                    } else if (dataType == "ENVELOPE ") {
                        // (NIL "Hello, World!" (("niuhuan" NIL "niuhuan" "hbjcxy.cn")) (("niuhuan" NIL "niuhuan" "hbjcxy.cn")) (("niuhuan" NIL "niuhuan" "hbjcxy.cn")) (("niuhuan" NIL "niuhuan" "hbjcxy.cn")) NIL NIL NIL NIL)
                        let enevelope = match (parseThisItem(reader)) {
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
                    }  else if (dataType == "BODY "|| dataType == "BODYSTRUCTURE ") {
                        // BODY ("text" "plain" ("charset" "us-ascii") NIL NIL "7bit" 3 0)
                        // BODY (("text" "plain" ("charset" "UTF-8") NIL NIL "base64" 22 1)("text" "html" ("charset" "UTF-8") NIL NIL "base64" 34 1)("application" "octet-stream" NIL NIL NIL "base64" 22) "mixed")
                        body = match (parseThisItem(reader)) {
                            case ImapValue.LIST(list) =>
                                ImapValue.LIST(list)
                            case _ =>
                                throw MailContentParseException("Invalid fetch ENVELOPE")
                        }
                    } else if (dataType == "BODY[TEXT] ") {
                        reader.readRune().getOrThrow({=>MailConnectExcption("Connect has been eof")}) // skip "{"
                        let sizeStr = reader.readUntil({rune => rune == r'}'}).getOrThrow({=>MailConnectExcption("Connect has been eof")}).trimRight("}")
                        let size = Int64.parse(sizeStr)
                        let builder = StringBuilder()
                        builder.append(String.fromUtf8(reader.readSize(size)))
                        let content = builder.toString();
                        let bodyOption = body.getOrThrow({=>MailContentParseException("Invalid fetch BODY. not found")})
                        let bodyList = match (bodyOption) {
                            case ImapValue.LIST(data) => data
                            case _ => throw MailContentParseException("Invalid fetch BODY TYPE")
                        }
                        match (bodyList[0]) {
                            case ImapValue.LIST(data) =>
                                var findBoundary = content.split("\r\n", removeEmpty: true)
                                var findBoundaryStr = findBoundary[findBoundary.size - 1].trimAscii()
                                let boundary = if (findBoundaryStr.startsWith("--") && findBoundaryStr.endsWith("--")) {
                                    findBoundaryStr = findBoundaryStr.trimLeft("--").trimRight("--")
                                } else {
                                    throw MailContentParseException("Invalid fetch BODY. findBoundaryStr")
                                }
                                let parts = MimeMutilParts()
                                bodyContext = parts
                                var sp = content.split("--${boundary}", removeEmpty: true)
                                if (!content.startsWith("--")) {
                                    sp = sp[1..]
                                }
                                for (mime in sp) {
                                    let content = mime.trimAscii()
                                    if (content == "--") {
                                        break
                                    }
                                    let (_, _, _, _, _, data)  = parseMailContent(content, isPartEntry: true)
                                    parts.append(data)
                                }
                            case ImapValue.STRING("TEXT") | ImapValue.STRING("text") =>
                                if (bodyList.size < 6) {
                                    throw MailContentParseException("Invalid fetch BODY. bodyList")
                                }
                                match (bodyList[5]) {
                                    case ImapValue.STRING("QUOTED-PRINTABLE")|ImapValue.STRING("quoted-printable") =>
                                        bodyContext = String.fromUtf8(parseQuotedPrintableMailContent(content))
                                    case ImapValue.STRING("BASE64")|ImapValue.STRING("base64") =>
                                        bodyContext = String.fromUtf8(parseBase64MailContent(content))
                                    case _ =>
                                        bodyContext = content
                                }
                            case _ =>
                                let (_, _, _, _, _, data)  = parseMailContent(builder.toString())
                                bodyContext = data
                        }
                    } else {
                        throw MailContentParseException("Invalid fetch: warn type ${dataType}")
                    }
                }
                let mail = ReceiveMail()
                mail.data = bodyContext
                mail.subject = subject
                mail.rcptTo = to
                mail.mailFrom = from
                emails.append((uid,mail))
            }
        }
        emails
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

private enum ImapValue {
    | NIL
    | STRING(String)
    | NUMBER(Int64)
    | LIST (ArrayList<ImapValue>)
}

extend ImapValue <: ToString {
    public func toString(): String {
        match (this) {
            case NIL =>
                "NIL"
            case STRING(str) =>
                "\"${str}\""
            case NUMBER(num) =>
                num.toString()
            case LIST(list) =>
                var builder = StringBuilder()
                builder.append("(")
                for (value in list) {
                    builder.append(value.toString())
                    builder.append(" ")
                }
                builder.append(")")
                builder.toString()
        }
    }
}

private func parseThisItem(reader: StreamReader): ImapValue {
    let builder = StringBuilder()
    var rune = reader.readRune().getOrThrow({=>MailConnectExcption("Connect has been eof")})
    builder.append(rune)
    match (rune) {
        case r"(" => 
            return parseList(reader)
        case r"\"" =>
            return parseString(reader)
        case "N" =>
            return parseNil(builder, reader)
        case _ =>
            if (rune >= r'0' && rune <= r'9') {
                let (value, end) = parseNumber(builder, reader)
                if (end) {
                    throw MailContentParseException("Invalid item todo : end")
                }
                return value
            }
            throw MailContentParseException("Invalid item : ${rune}")
    }
}

private func parseList(reader: StreamReader): ImapValue {
    let values = ArrayList<ImapValue>()
    while (true) {
        let rune = reader.readRune().getOrThrow({=>MailConnectExcption("Connect has been eof")})
        match (rune) {
            case " " =>
                continue
            case ")" =>
                break
            case r"(" =>
                values.append(parseList(reader))
            case r"\"" =>
                values.append(parseString(reader))
            case "N" =>
                values.append(parseNil(StringBuilder("N"), reader))
            case _ =>
                if (rune >= r'0' && rune <= r'9') {
                    let (value, end) = parseNumber(StringBuilder(rune), reader)
                    values.append(value)
                    if (end) {
                        break
                    }
                } else {
                    throw MailContentParseException("Invalid parse : ${rune}")
                }
        }
    }
    ImapValue.LIST(values)
}

private func parseNil(builder: StringBuilder, reader: StreamReader): ImapValue {
    for (_ in 0..2) {
        let rune = reader.readRune().getOrThrow({=>MailConnectExcption("Connect has been eof")})
        builder.append(rune)
    }
    if (builder.toString() == "NIL") {
        return ImapValue.NIL
    } else {
        throw MailContentParseException("Invalid NIL")
    }
}

private func parseString(reader: StreamReader): ImapValue {
    let cBuilder = StringBuilder()
    var inEscape = false
    while (true) {
        let rune = reader.readRune().getOrThrow({=>MailConnectExcption("Connect has been eof")})
        if (inEscape) {
            inEscape = false
            cBuilder.append(rune)
        } else if (rune == r'\\') {
            inEscape = true
        } else if (rune == r'"') {
            break
        } else {
            cBuilder.append(rune)
        }
    }
    return ImapValue.STRING(cBuilder.toString())
}

private func parseNumber(builder: StringBuilder, reader: StreamReader): (ImapValue, Bool) {
    var end = false
    while (true) {
        let rune = reader.readRune().getOrThrow({=>MailConnectExcption("Connect has been eof")})
        if (rune >= r'0' && rune <= r'9') {
            continue
        } else if (rune == r' ') {
            break
        } else if (rune == r')') {
            end = true
            break
        } else {
            throw MailContentParseException("Invalid NUMBER : ${rune}")
        }
    }
    return (ImapValue.NUMBER(Int64.parse(builder.toString())), end)
}

private func parseImapAddress(list: ArrayList<ImapValue>): MailAddress {
    if (list.size < 4) {
        throw MailContentParseException("Invalid fetch ENVELOPE")
    }
    var name = getImapValueString(list[0])
    var mailId = getImapValueString(list[2])
    var mailDomain = getImapValueString(list[3])
    MailAddress(name, "${mailId}@${mailDomain}")
}

private func getImapValueString(value: ImapValue): String {
    match (value) {
        case ImapValue.STRING(str) =>
            str
        case _ =>
            ""
    }
}
