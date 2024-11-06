package cj_mail.smtp

import std.socket.*
import std.io.*
import net.tls.*
import std.regex.*
import std.collection.*
import encoding.base64.*
import log.*
import std.random.*

@Default
@AllArgsConstructor
public class SendMail {
   public var mailFrom: MailAddress
   public var rcptTo: Array<MailAddress>
   public var subject: String
   public var data: MailContent = ""
}

public class Smtp {

   let logger = getGlobalLogger(("cj_mail", "Smtp"))

   public var host: String = ""
   public var tlsPort: UInt16 = 587

   public var authTypes: Array<String> = []

   private var lastSession: ?TlsSession = None
   private var tlsTlsSocket: ?TlsSocket = None
   private var reader: ?StringReader<IOStream> = None
   private var writer: ?StringWriter<IOStream> = None

   public init(){
   }

   private func writeCommand(command: String) {
      let writer = this.writer.getOrThrow()
      logger.debug("C: ${command}")
      writer.write(command)
      writer.write("\r\n")
      writer.flush()
   }

   private func readCommand() : SmtpResponse {
      let serverResponse = SmtpResponse()
      let reader = this.reader.getOrThrow()
      while (true) {
         var line = reader.readln().getOrThrow()
         logger.debug("S: ${line}")
         match (responseBaseRegex.matches(line)) {
            case Some(r) =>
               let code = Int64.parse(r.matchStr(1))
               let minusOrSp = r.matchStr(2)
               let message = r.matchStr(3)
               if (serverResponse.code == 0) {
                  serverResponse.code = code
               } else if (serverResponse.code != code) {
                  throw  Exception("Invalid response code")
               }
               if (serverResponse.message != "") {
                  serverResponse.message += "\n"
               }
               serverResponse.message += message
               if (minusOrSp == " ") {
                  if (serverResponse.code / 100 > 3) {
                     // 250 OK
                     // 334 VXNlcm5hbWU6
                     // 354 Start mail input; end with <CRLF>.<CRLF>
                     throw SmtpException(serverResponse)
                  }
                  return serverResponse
               }
            case None =>
               throw Exception("Invalid response")
         }
      }
      throw Exception("Invalid response")
   }

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
      // init smtp
      readCommand() // Server Hello
      writeCommand("EHLO ${host}")
      let ehloResponse = readCommand()
      for (msg in ehloResponse.message.split("\n")) {
         if (msg.startsWith("AUTH ")) {
            this.authTypes = msg.split(" ")
         }
      }
   }
   
   public func plain(username: String, password: String) {
      var arrList = ArrayList<Byte>()
      arrList.append(0)
      arrList.appendAll(username.toArray())
      arrList.append(0)
      arrList.appendAll(password.toArray())
      var arr = arrList.toArray()
      writeCommand("AUTH PLAIN ${toBase64String(arr)}")
      readCommand()
   }

   public func login(username: String, password: String) {
      writeCommand("AUTH LOGIN")
      readCommand()
      writeCommand(toBase64String(username.toArray()))
      readCommand()
      writeCommand(toBase64String(password.toArray()))
      readCommand()
   }

   public func send(mail: SendMail) {
      writeCommand("MAIL FROM:<${mail.mailFrom.address}>")
      readCommand()
      for (rcpt in mail.rcptTo) {
         writeCommand("RCPT TO:<${rcpt.address}>")
         readCommand()
      }
      writeCommand("DATA")
      readCommand()
      putMailData(mail)
      writeCommand(".")
      writeCommand("")
      readCommand()
   }


   private func putMailData(mail: SendMail) {
      if (let Some(data) <- mail.data as String) {
         putMailAddresses(mail)
         putMailSubject(mail)
         writeCommand("")
         for (line in data.split("\n")) {
            if (line == ".") {
               writeCommand("&#46;")
            } else {
               writeCommand(line)
            }   
         }
      } else if (let Some(data) <- mail.data as MimeText) {
         putMailAddresses(mail)
         putMailSubject(mail)
         writeCommand("Content-Type: ${data.contentType}; charset=\"UTF-8\"")
         writeCommand("MIME-Version: 1.0")
         writeCommand("Content-Transfer-Encoding: base64")
         writeCommand("")
         writeCommand(toBase64String(data.text.toArray()))
      } else if (let Some(data) <- mail.data as MutilPartContent) {
         let boundary = randomBoundary()
         writeCommand("Content-Type: multipart/mixed; boundary=\"${boundary}\"")
         writeCommand("MIME-Version: 1.0")
         putMailAddresses(mail)
         putMailSubject(mail)
         for (part in data) {
            writeCommand("")
            writeCommand("--${boundary}")
            if (let Some(part) <- part as String) {
               writeCommand("Content-Type: text/plain; charset=\"UTF-8\"")
               writeCommand("Content-Transfer-Encoding: base64")
               writeCommand("")
               writeCommand(toBase64String(part.toArray()))
            } else if (let Some(part) <- part as MimeText) {
               writeCommand("Content-Type: ${part.contentType}; charset=\"UTF-8\"")
               writeCommand("Content-Transfer-Encoding: base64")
               writeCommand("")
               writeCommand(toBase64String(part.text.toArray()))
            } else if (let Some(part) <- part as MimeFile) {
               writeCommand("Content-Type: ${part.contentType}")
               writeCommand("Content-Transfer-Encoding: base64")
               for (header in part.headers) {
                  writeCommand("${header[0]}: ${header[1]}")
               }
               writeCommand("")
               writeCommand(toBase64String(part.data))
            }
         }
         writeCommand("")
         writeCommand("--${boundary}--")
      }
   }

   private func randomBoundary() : String {
      let chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
      let m: Random = Random()
      let str = ArrayList<Rune>()
      for (_ in 0..30) {
         var idx = m.nextInt64();
         if (idx < 0) {
            idx = -idx
         }
         idx = idx % chars.size
         str.append(Rune((chars[idx])))
      }
      String(str.toArray())
   }

   private func putMailSubject(mail: SendMail) {
      if (mail.subject != "") {
         writeCommand("Subject: ${mail.subject}")
      }
   }

   private func putMailAddresses(mail: SendMail) {
      writeCommand("From: ${mail.mailFrom.toString()}")
      var to = ""
      for (rcpt in mail.rcptTo) {
         if (to != "") {
            to += ", "
         }
         to += rcpt.toString()
      }
      writeCommand("To: ${to}")
   }

   public func quit() {
      writeCommand("QUIT")
      readCommand()
   }

   public func close() {
         tlsTlsSocket.getOrThrow().close()
   }
}
