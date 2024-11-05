package cj_mail

import cj_lombok.*

import std.socket.*
import std.io.*
import net.tls.*
import std.regex.*
import std.collection.*
import encoding.base64.*
import log.*

let responseBaseRegex = Regex("^(\\d\\d\\d)([\\- ])([\\S\\s]+)$")

@Default
@ToString
public class ServerResponse {
   public var code: Int64
   public var message: String
}

@AllArgsConstructor
@ToString
public class ServerException <: Exception {
   public var serverResponse: ServerResponse
}

@Default
@AllArgsConstructor
public class MailAddress <: ToString {
   public var name: String
   public var address: String

   public func toString() {
      "${name}<${address}>"
   }
}

@Default
@AllArgsConstructor
public class SendMail {
   public var mailFrom: MailAddress
   public var rcptTo: Array<MailAddress>
   public var subject: String
   public var data: String
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

   private func readCommand() : ServerResponse {
      let serverResponse = ServerResponse()
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
                     throw ServerException(serverResponse)
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
      writeCommand("From: ${mail.mailFrom.toString()}")
      var to = ""
      for (rcpt in mail.rcptTo) {
         if (to != "") {
            to += ", "
         }
         to += rcpt.toString()
      }
      writeCommand("To: ${to}")
      if (mail.subject != "") {
         writeCommand("Subject: ${mail.subject}")
      }
      writeCommand("")
      for (line in mail.data.split("\n")) {
         if (line == ".") {
            writeCommand("&#46;")
         } else {
            writeCommand(line)
         }   
      }
      writeCommand(".")
      writeCommand("")
      readCommand()
   }

   public func quit() {
      writeCommand("QUIT")
      readCommand()
   }

   public func close() {
         tlsTlsSocket.getOrThrow().close()
   }
}

