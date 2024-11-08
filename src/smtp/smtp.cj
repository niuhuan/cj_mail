package cj_mail.smtp

import std.socket.*
import std.io.*
import net.tls.*
import std.regex.*
import std.collection.*
import encoding.base64.*
import log.*
import std.random.*
import cj_mail.commons.*
import std.convert.*

let responseBaseRegex = Regex("^(\\d\\d\\d)([\\- ])([\\S\\s]+)$")

public class Smtp {

   let logger = getGlobalLogger(("cj_mail", "Smtp"))

   public var host: String = ""
   public var tlsPort: UInt16 = 587

   public var authTypes: Array<String> = []
   public var connection: ?MailConnection = None

   public init(){
   }

   private func writeCommand(command: String) {
      let writer = this.connection.getOrThrow({=>MailConnectExcption("Not connected")})
      logger.trace("C: ${command}")
      writer.write(command)
      writer.write("\r\n")
      writer.flush()
   }

   private func readCommand() : SmtpResponse {
      let reader = this.connection.getOrThrow({=>MailConnectExcption("Not connected")})
      let serverResponse = SmtpResponse()
      while (true) {
         var line = reader.readln().getOrThrow({=>MailConnectExcption("Connect has been eof")})
         logger.trace("S: ${line}")
         match (responseBaseRegex.matches(line)) {
            case Some(r) =>
               let code = Int64.parse(r.matchStr(1))
               let minusOrSp = r.matchStr(2)
               let message = r.matchStr(3)
               if (serverResponse.code == 0) {
                  serverResponse.code = code
               } else if (serverResponse.code != code) {
                  throw  MailContentParseException("Inconsistent code", line)
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
               throw MailContentParseException("Invalid response", line)
         }
      }
      // should not reach here
      throw MailContentParseException("Invalid response")
   }

   public func connect() {
      this.connection =defaultTlsConnect(host, tlsPort)
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
      putMailData(mail.mailFrom, mail.rcptTo, mail.cc, mail.bcc, mail.subject, mail.data)
      writeCommand(".")
      writeCommand("")
      readCommand()
   }


   private func putMailData(from: Option<MailAddress>, to: ArrayList<MailAddress>, cc: ArrayList<MailAddress>, bcc: ArrayList<MailAddress>, subject: String, mailData: MailContent): Unit {
      if (let Some(data) <- mailData as String) {
         putMailAddressesSubject(from, to, cc, bcc, subject)
         writeCommand("")
         for (line in data.split("\n")) {
            if (line == ".") {
               writeCommand("&#46;")
            } else {
               writeCommand(line)
            }   
         }
      } else if (let Some(data) <- mailData as MimeText) {
         putMailAddressesSubject(from, to, cc, bcc, subject)
         writeCommand("Content-Type: ${data.contentType}; charset=\"UTF-8\"")
         writeCommand("MIME-Version: 1.0")
         writeCommand("Content-Transfer-Encoding: base64")
         if (data.contentId != "") {
            writeCommand("Content-ID: <${data.contentId}>")
         }
         writeCommand("")
         writeCommand(toBase64String(data.text.toArray()))
      } else if (let Some(data) <- mailData as MimeFile) {
         putMailAddressesSubject(from, to, cc, bcc, subject)
         writeCommand("Content-Type: ${data.contentType}; name=\"${data.contentType}\"")
         writeCommand("Content-Disposition: attachment; filename=\"${data.fileName}\"")
         writeCommand("MIME-Version: 1.0")
         writeCommand("Content-Transfer-Encoding: base64")
         if (data.contentId != "") {
            writeCommand("Content-ID: <${data.contentId}>")
         }
         writeCommand("")
         writeCommand(toBase64String(data.data.toArray()))
      } else if (let Some(data) <- mailData as MimeMutilParts) {
         let boundary = randomBoundary()
         let mimeType = if (data.contentType == "") {
            "multipart/mixed"
         } else {
            data.contentType
         }
         writeCommand("Content-Type: ${mimeType}; boundary=\"${boundary}\"")
         writeCommand("MIME-Version: 1.0")
         putMailAddressesSubject(from, to, cc, bcc, subject)
         if (data.contentId != "") {
            writeCommand("Content-ID: <${data.contentId}>")
         }
         for (part in data) {
            writeCommand("")
            writeCommand("--${boundary}")
            putMailData(None, ArrayList<MailAddress>(), ArrayList<MailAddress>(), ArrayList<MailAddress>(), "", part)
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
      let res = String(str.toArray())
      "===============${res}=="
   }


   private func putMailAddressesSubject(from: Option<MailAddress>, rcptTo: ArrayList<MailAddress>, ccTo: ArrayList<MailAddress>, bccTo: ArrayList<MailAddress>, subject: String) {
      if (from.isSome()) {
         writeCommand("From: ${from.getOrThrow().toString()}")
      }
      if (rcptTo.size > 0) {
         var to = ""
         for (rcpt in rcptTo) {
            if (to != "") {
               to += ", "
            }
            to += rcpt.toString()
         }
         writeCommand("To: ${to}")
      }
      if (ccTo.size > 0) {
         var ccStr = ""
         for (cc in ccTo) {
            if (ccStr != "") {
               ccStr += ", "
            }
            ccStr += cc.toString()
         }
         writeCommand("Cc: ${ccStr}")
      }
      if (bccTo.size > 0) {
         var bccStr = ""
         for (bcc in bccTo) {
            if (bccStr != "") {
               bccStr += ", "
            }
            bccStr += bcc.toString()
         }
         writeCommand("Bcc: ${bccStr}")
      }
      if (subject != "") {
         writeCommand("Subject: ${subject}")
      }
   }

   public func quit() {
      writeCommand("QUIT")
      readCommand()
   }

   public func disconnect() {
         connection.getOrThrow({=>MailConnectExcption("Not connected")}).disconnect()
   }
}
