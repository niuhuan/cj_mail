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
        let reader = this.connection.getOrThrow({=>MailConnectExcption("Not connected")})
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
                             let regex = Regex("^\\* \\d+ FETCH [\\S\\s]+ \\{(\\d+)\\}$")
                             let matcher = regex.matcher(line);
                             match(matcher.find()) {
                                    case Some(s) =>
                                        let len = Int64.parse(s.matchStr(1))
                                        logger.trace(".. for read Rune * ${len} from server ..")
                                        for (_ in 0..len) {
                                            builder.append(reader.read().getOrThrow({=>MailConnectExcption("Connect has been eof")}))
                                        }
                                        let line = reader.readln().getOrThrow({=>MailConnectExcption("Connect has been eof")})
                                        logger.trace(".. line left : ${line} ..")
                                        builder.append(line)
                                    case None => ()
                             }
                        }
                        continue
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
      this.connection =defaultTlsConnect(host, tlsPort)
        readCommand(None) // Server Hello
    }

    public func login(username: String, password: String) {
        let idx = nextCmdIdx();
        writeCommand("${idx} LOGIN ${username} ${password}")
        readCommand(idx)
    }

    public func select(mailbox: String): MailboxState {
        let idx = nextCmdIdx();
        writeCommand("${idx} SELECT ${mailbox}")
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

    public func list(referenceName: String, mailboxName: String): String {
        let idx = nextCmdIdx();
        writeCommand("${idx} LIST \"${escapingDoubleQuote(referenceName)}\" \"${escapingDoubleQuote(mailboxName)}\"")
        readCommand(idx)
    }

    private func escapingDoubleQuote(str: String): String {
        str.replace("\"", "\\\"")
    }

}