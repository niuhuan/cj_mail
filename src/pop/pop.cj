
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

let popStatePattern = Regex("^\\+OK (\\d+) (\\d+)$")

@AllArgsConstructor
public class PopException <: Exception {
    public var serverResponse: String
}

public class Pop {

    let logger = getGlobalLogger(("cj_mail", "Pop"))

    public var host: String =  ""
    public var tlsPort: UInt16 = 995

    private var lastSession: ?TlsSession = None
    private var tlsTlsSocket: ?TlsSocket = None
    private var reader: ?StringReader<IOStream> = None
    private var writer: ?StringWriter<IOStream> = None

   public func connect() {
      // init tls
      let socket = TcpSocket(host, tlsPort)
      socket.connect()
      var config = TlsClientConfig()
      config.verifyMode = TrustAll
      config.alpnProtocolsList = ["h2"]
      let tls = TlsSocket.client(socket, clientConfig: config, session: lastSession)
      this.tlsTlsSocket = Some(tls)
      tls.handshake()
      lastSession = tls.session
      reader = StringReader(tls)
      writer = StringWriter(tls)
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
        let reader = this.reader.getOrThrow()
        let line = reader.readln().getOrThrow()
        logger.trace("S: ${line}")
        if (line.startsWith("-ERR")) {
            throw PopException(line)
        }
        line
    }

   public func writeCommand(command: String) {
        let writer = this.writer.getOrThrow()
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

    /*
             Examples:
             C: LIST
             S: +OK 2 messages (320 octets)
             S: 1 120
             S: 2 200
             S: .
               ...
             C: LIST 2
             S: +OK 2 200
               ...
             C: LIST 3
             S: -ERR no such message, only 2 messages in maildrop
    */

    public func list() :(Int64, ArrayList<(Int64, Int64)>) {
        writeCommand("LIST")
        let line = readCommand()
        if (!line.startsWith("+OK")) {
            throw Exception("Invalid response : ${line}")
        }
        let parts = line.split(" ")
        let count = Int64.parse(parts[1])
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
        let parts = response.split(" ")
        if (parts.size < 2) {
            throw Exception("Invalid response")
        }
        let idx = Int64.parse(parts[0])
        let size = Int64.parse(parts[1])
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
        var content = ""
        while (true) {
            let line = readCommand()
            if (line == ".") {
                break
            }
            content += line + "\r\n"
        }
        (size, content)
    }

    public func retrParse(msg: Int64) : (Int64, ReceiveMail) {
        let (size, content) = retr(msg)
        var from = ""
        var to = ""
        var subject = ""
        var contentType = ""
        var contentTransferEncoding =""
        // read header
        let lines = content.lazySplit("\r\n")
        while(true){
            let line = lines.next().getOrThrow()
            if (line == "") {
                break
            } else if (!line.contains(":")) {
                throw Exception("Invalid response : ${line}")
            }
            let parts = line.split(":")
            if (parts.size < 2) {
                throw Exception("Invalid response : ${line}")
            }
            let key = parts[0].trimAscii()
            let value = parts[1].trimAscii()
            match (key) {
                case "From" => from = value
                case "To" => to = value
                case "Subject" => subject = value
                case "Content-Type" => contentType = value
                case "Content-Transfer-Encoding" => contentTransferEncoding = value
                case _ => 
                    logger.debug("Ignore header : ${key}")
            }
        }
        // parse header
        let mail = ReceiveMail()
        if (from != "") {
            mail.mailFrom = parseMailAddress(from)
        }
        if (to != "") {
            mail.rcptTo = parseMailAddresses(to)
        }
        mail.subject = subject
        // "=?{charset}?{encoding}?{encoded_text}?="
        if (mail.subject.startsWith("=?utf-8?b?") && mail.subject.endsWith("?=")) {
            let encoded = mail.subject[10..mail.subject.size-2]
            mail.subject = String.fromUtf8(fromBase64String(encoded).getOrThrow())
        }
        // todo ?q? quopri
        // parse mime
        let parts = contentType.split(";")
        let contentTypeMime = parts[0].trimAscii()
        var boundary=""
        var charset=""
        for (p in parts[1..]) {
            match (p.indexOf("=")) {
                case Some(idx) =>
                    let key = p[0..idx].trimAscii()
                    var value = p[idx+1..].trimAscii()
                    if (value.startsWith("\"") && value.endsWith("\"")) {
                        value = value[1..value.size-1]
                    }
                    match (key) {
                        case "boundary" => boundary = value
                        case "charset" => charset = value
                        case _ => 
                            logger.debug("Ignore content type : ${key}")
                    }
                case None =>
                    continue
            }
        }
        // parse body
        if (contentTypeMime.startsWith("text/")) {
            var textBody = ""
            while(let Some(line) <- lines.next()) {
                textBody += line + "\r\n"
            }
            if ("base64" == contentTransferEncoding) {
                textBody = String.fromUtf8(fromBase64String(textBody).getOrThrow())
            }
            mail.data = MimeText(textBody, contentTypeMime)
            return (size, mail)
        } else if (contentTypeMime.startsWith("multipart/")) {
            var line =  lines.next().getOrThrow()
            // first boundary
            if (!line.startsWith("--${boundary}")) {
                throw Exception("Invalid response : ${line}")
            }
            // blank content
            if (line == "--${boundary}--") {
                mail.data = MutilPartContent()
                return (size, mail)
            }
            // children
            let parts = ArrayList<MutilPart>()
            var mutilPartContentTransferEncoding = ""
            var mutilPartHeaders = ArrayList<(String,String)>()
            var mutilPartContentMime = ""
            var mutilPartContentCharset = ""
            var mutilPartBoundary = ""
            var mutilPartCharset = ""
            while (true) {
                var hasContinue = false
                var hasBreak = false
                while(true) {
                    line = lines.next().getOrThrow()
                    if (line == "") {
                        break
                    } else if (!line.contains(":")) {
                        throw Exception("Invalid response : ${line}")
                    }
                    if (line.startsWith("--${boundary}")) {
                        hasContinue = true
                        if (line == "--${boundary}--") {
                            hasBreak = true
                        }
                        // blank content
                        if (mutilPartContentMime.contains("text/")) {
                            parts.append(MimeText("", mutilPartContentMime))
                        } else {
                            parts.append(MimeFile([], mutilPartContentMime))
                        }
                        mutilPartContentTransferEncoding = ""
                        mutilPartHeaders = ArrayList<(String,String)>()
                        mutilPartContentMime = ""
                        mutilPartContentCharset = ""
                        mutilPartBoundary = ""
                        mutilPartCharset = ""
                        break
                    }
                    let split = line.split(":")
                    if (split.size < 2) {
                        throw Exception("Invalid response : ${line}")
                    }
                    let key = split[0].trimAscii()
                    let value = split[1].trimAscii()
                    var mutilPartContentType = ""
                    match (key) {
                        case "Content-Type" => 
                            mutilPartContentType = value
                            let mpc = value.split(";")
                            mutilPartContentMime = mpc[0].trimAscii()
                            for (p in mpc[1..]) {
                                match (p.indexOf("=")) {
                                    case Some(idx) =>
                                        let key = p[0..idx].trimAscii()
                                        var value = p[idx+1..].trimAscii()
                                        if (value.startsWith("\"") && value.endsWith("\"")) {
                                            value = value[1..value.size-1]
                                        }
                                        match (key) {
                                            case "boundary" => mutilPartBoundary = value
                                            case "charset" => mutilPartCharset = value
                                            case _ => 
                                                logger.debug("Ignore content type : ${key}")
                                        }
                                    case None =>
                                        continue
                                }
                                let kv = p.split("=")
                                if (kv.size < 2) {
                                    continue
                                }
                            }
                        case "Content-Transfer-Encoding" => mutilPartContentTransferEncoding = value
                        case _ => 
                            mutilPartHeaders.append((key, value))
                    }
                }
                if (hasBreak) {
                    break
                }
                if (hasContinue) {
                    continue
                }
                var content = ""
                while(true) {
                    line = lines.next().getOrThrow()
                    if (line.startsWith("--${boundary}")) {
                        hasContinue = true
                        if (line == "--${boundary}--") {
                            hasBreak = true
                        }
                        if (mutilPartContentMime.contains("text/")) {
                            if ("base64" == mutilPartContentTransferEncoding) {
                                content = String.fromUtf8(fromBase64String(content.trimAscii().replace("\r\n", "")).getOrThrow())
                            }
                            parts.append(MimeText(content, mutilPartContentMime))
                        } else {
                            if ("base64" == mutilPartContentTransferEncoding) {
                                 parts.append(MimeFile(fromBase64String(content.trimAscii().replace("\r\n", "")).getOrThrow(), mutilPartContentMime))
                            } else {
                                 parts.append(MimeFile(content.toArray(), mutilPartContentMime))
                            }
                        }
                        mutilPartContentTransferEncoding = ""
                        mutilPartHeaders = ArrayList<(String,String)>()
                        mutilPartContentMime = ""
                        mutilPartContentCharset = ""
                        mutilPartBoundary = ""
                        mutilPartCharset = ""
                        break
                    }
                    content += line + "\r\n"
                }
                if (hasBreak) {
                    break
                }
                if (hasContinue) {
                    continue
                }
            }
            mail.data = parts
            return (size, mail)
        } else {
            var textBody = ""
            while(let Some(line) <- lines.next()) {
                textBody += line + "\r\n"
            }
            if ("base64" == contentTransferEncoding) {
                textBody = String.fromUtf8(fromBase64String(textBody).getOrThrow())
            }
            mail.data = MimeText(textBody, contentTypeMime)
            return (size, mail)
        }
        // text mail (or other)
        mail.data = content
        return (size, mail)
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
         tlsTlsSocket.getOrThrow().close()
   }
    
}
