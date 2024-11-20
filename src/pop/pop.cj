
package cj_mail.pop

import net.tls.*
import std.socket.*
import std.collection.*
import std.io.*
import cj_lombok.*
import std.regex.*
import log.*
import cj_mail.commons.*
import encoding.base64.*
import cj_mail.exception.*

let popStatePattern = Regex("^\\+OK (\\d+) (\\d+)$")

@AllArgsConstructor
public class PopException <: Exception {
    public var serverResponse: String
}

public class Pop {

    let logger = getGlobalLogger(("cj_mail", "Pop"))

    public var host: String =  ""
    public var tlsPort: UInt16 = 995

   public var connection: ?MailConnection = None

    public func connect() {
        this.connection = defaultTlsConnect(host, tlsPort)
        readCommand() // Server Hello
    }

    public func connect(socket: StreamingSocket) {
        this.connection = mailConnection(socket)
        readCommand() // Server Hello
    }

    public func noop() {
        writeCommand("NOOP")
        readCommand()
    }

    public func rest() {
        writeCommand("RSET")
        readCommand()
    }

    public func readCommand(): String {
        let reader = this.connection.getOrThrow({=>MailConnectExcption("Not connected")}).reader
        let line = reader.readln().getOrThrow({=>MailConnectExcption("Connect has been eof")})
        logger.trace("S: ${line}")
        if (line.toAsciiLower().startsWith("-ERR")) {
            throw PopException(line)
        }
        line
    }

    public func writeCommand(command: String) {
        let writer = this.connection.getOrThrow({=>MailConnectExcption("Not connected")}).writer
        logger.trace("C: ${command}")
        writer.write(command)
        writer.write("\r\n")
        writer.flush()
    }

    public func apop(username: String, password: String) {
        writeCommand("APOP ${username} ${password}")
        readCommand()
    }

    public func user(username: String) {
        writeCommand("USER ${username}")
        readCommand()
    }

    public func pass(password: String) {
        writeCommand("PASS ${password}")
        readCommand()
    }

    public func auth(username: String, password: String) {
        user(username)
        pass(password)
    }

    public func stat(): Int64 {
        writeCommand("STAT")
        let line = readCommand()
        match (popStatePattern.matches(line)) {
            case Some(r) =>
                let count = Int64.parse(r.matchStr(1))
                count
            case None =>
                throw Exception("Invalid response")
        }
    }

    public func list() :(Int64, ArrayList<(Int64, Int64)>) {
        writeCommand("LIST")
        let line = readCommand()
        if (!line.startsWith("+OK")) {
            throw Exception("Invalid response : ${line}")
        }
        var count = -1
        if (line != "+OK") {
            let parts = line.split(" ")
            count = Int64.parse(parts[1])
        }
        let mails = ArrayList<(Int64, Int64)>()
        while (true) {
            let line = readCommand()
            if (line == ".") {
                break
            }
            let parts = line.split(" ")
            if (parts.size < 2) {
                throw Exception("Invalid response")
            }
            let msg = Int64.parse(parts[0])
            let size = Int64.parse(parts[1])
            mails.append((msg, size))
        }
        (count, mails)
    }

    public func list(msg: Int64) : (Int64, Int64) {
        writeCommand("LIST ${msg}")
        let response = readCommand()
        let matcher = Regex("^(\\+OK )?(\\d+) (\\d+)$").matches(response).getOrThrow({=>Exception("Invalid response")})
        let idx = Int64.parse(matcher.matchStr(2))
        let size = Int64.parse(matcher.matchStr(3))
        (idx, size)
    }

    public func retr(msg : Int64) : (Int64, String) {
        writeCommand("RETR ${msg}")
        let lien = readCommand()
        let split = lien.split(" ")
        if (split.size < 2) {
            throw Exception("Invalid response")
        }
        let size = Int64.parse(split[1])
        var content = StringBuilder()
        while (true) {
            let line = readCommand()
            if (line == ".") {
                break
            }
            content.append(line)
            content.append("\r\n")
        }
        (size, content.toString())
    }

    public func retrParse(msg: Int64) : ReceiveMail {
        let (_, content) = retr(msg)
        let (from, to, cc, bcc, subject, data) = parseMailContent(content)
        
        let mail = ReceiveMail()
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
        mail
    }

    public func dele(msg: Int64) {
        writeCommand("DELE ${msg}")
        readCommand()
    }

   public func quit() {
      writeCommand("QUIT")
      readCommand()
   }

   public func disconnect() {
         connection.getOrThrow({=>MailConnectExcption("Not connected")}).disconnect()
   }
    
}
