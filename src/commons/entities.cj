package cj_mail.commons

import std.collection.*
import std.io.*
import std.regex.*
import cj_lombok.*
import encoding.base64.*
import log.*


let logger = getGlobalLogger(("cj_mail", "Parser"))
let mailAddressPattern = Regex("^(.*)?<(.*)>$")


/// MailAdress

@Default
@AllArgsConstructor
public class MailAddress <: ToString {
   public var name: String
   public var address: String

   public func toString() {
      "${name}<${address}>"
   }
}

public func parseMailAddress(address: String): MailAddress {
   match (mailAddressPattern.matches(address)) {
      case Some(matches) =>
         let name = matches.matchStr(1).trimAscii()
         let addr = matches.matchStr(2).trimAscii()
         MailAddress(name, addr)
      case None =>
         MailAddress("", address)
   }
}

public func parseMailAddresses(addresses: String): ArrayList<MailAddress> {
   let parts = addresses.lazySplit(",")
   let result = ArrayList<MailAddress>()
   for (part in parts) {
      var text = part.trimAscii()
      if (text == "") {
         continue
      }
      result.append(parseMailAddress(text))
   }
   result
}

/// Mail

@Default
@AllArgsConstructor
public open class Mail {
   public var mailFrom: MailAddress
   public var rcptTo: ArrayList<MailAddress>
   public var cc: ArrayList<MailAddress>
   public var bcc: ArrayList<MailAddress>
   public var subject: String
   public var data: MailContent = ""
}

extend Mail <: ToString {
   public func toString(): String {
      if (this is ImapReceiveMail) {
         let mail = (this as ImapReceiveMail).getOrThrow()
         return "ImapReceiveMail(mailFrom=${mail.mailFrom}, rcptTo=${mail.rcptTo}, cc=${mail.cc}, bcc=${mail.bcc}, subject=${mail.subject}, data=${mail.data})"
      }
      "Mail(mailFrom=${mailFrom}, rcptTo=${rcptTo}, cc=${cc}, bcc=${bcc}, subject=${subject}, data=${data})"
   }
}

public type SendMail = Mail
public type ReceiveMail = Mail

public class ImapReceiveMail <: ReceiveMail {
   public var idx: Int64
   public var uid: Int64
   public var size: Int64
   public var flags: ArrayList<String>
   public var messageId: String
   public init() {
      super()
      idx = -1
      uid = -1
      size = -1
      flags = ArrayList()
      messageId = ""
   }
}

/// MailContent: MutilParts / MimeFile or MimeText

public interface MailContent <: ToString {
}

extend String <: MailContent{
}

@Default
public class MimeText <: MailContent {
     public var text: String = ""
     public var contentType: String = ""
     public var contentId: String = ""
     public var headers: ArrayList<(String, String)> = ArrayList()

     public init(text: String, contentType: String) {
        this.text = text
        this.contentType = contentType
     }

     public func toString(): String {
         "MimeText(contentType=${contentType}, size=${text.size}, text=${text})"
     }
}

@Default
public class MimeFile <: MailContent {
     public var data: Array<Byte>
     public var contentId: String
     public var contentType: String
     public var fileName: String
     public var headers: ArrayList<(String, String)>

     public init(data: Array<Byte>, contentType: String) {
        this.data = data
        this.contentType = contentType
     }

     public init(data: Array<Byte>, contentType: String, headers: ArrayList<(String, String)>) {
        this.data = data
        this.contentType = contentType
        this.headers = headers
     }

     public func addHeader(name: String, value: String) {
        headers.append((name, value))
     }

     public func toString(): String {
         "MimeFile(contentType=${contentType}, size=${data.size})"
     }
}

@Default
public class MimeMutilParts <: Collection<MailContent> & MailContent {
   public var contentType: String = ""
   public var contentId: String = ""
   public var headers: ArrayList<(String, String)> = ArrayList()
   public var parts: ArrayList<MailContent> = ArrayList()

   public func iterator() : Iterator<MailContent> {
      parts.iterator()
   }

   public prop size: Int64 {
        get() { parts.size }
   }

   public func isEmpty(): Bool {
      parts.isEmpty()
   }

   public func append(part: MailContent) {
      parts.append(part)
   }

   public func toString(): String {
      "MimeMutilParts(contentType=${contentType}, size=${parts.size}, parts=${parts})"
   }
}

// parse conent (pop / imap)

public enum MailContentType {
   | Main
   | Par
}

public func parseMailContent(content: String, isPartEntry!: Bool = false) : (String, String, String, String, String, MailContent) {
   var onlyHeaders = false
   var from = ""
   var to = ""
   var cc = ""
   var bcc = ""
   var subject = ""
   var contentId = ""
   var contentType = ""
   var contentTransferEncoding =""
   var headers = ArrayList<(String, String)>()
   // read header
   let lines = content.lazySplit("\r\n", removeEmpty: true)
   // foreach Header
   var headerLine = ""
   func parseHeader() {
      if (headerLine == "") {
         return
      }
      let parts = headerLine.trimAscii().split(":", 2, removeEmpty: true)
      if (parts.size < 2) {
            throw MailContentParseException("Missing colon in mail content header value", headerLine)
      }
      let key = parts[0].trimAscii()
      let value = parts[1].trimAscii()
      match (key) {
            case "From" => from = value
            case "To" => to = value
            case "Cc" => cc = value
            case "Bcc" => bcc = value
            case "Subject" => subject = value
            case "Content-ID" => contentId = value
            case "Content-Type" => contentType = value
            case "Content-Transfer-Encoding" => contentTransferEncoding = value
            case _ => 
                  headers.append((key, value))
      }
      headerLine = ""
   }
   var first = true;
   while(true){
      let lineOption = lines.next()
      let line = match (lineOption) {
            case Some(l) => l
            case None => 
               onlyHeaders = true
               break
      }
      if (first && !line.contains(":")) {
            if (isPartEntry) {
               return (from, to, cc, bcc, subject, content)
            }
            throw MailContentParseException("Missing colon in mail content header", line)
      } else {
         first = false
      }
      if (line == "") {
            parseHeader()
            break
      } else if (line.contains(":")) {
            parseHeader()
            headerLine += line
            headerLine += "\r\n"
      } else if (Regex("^\\s+[^\n]+").matches(line).isSome()) {
            headerLine += " "
            headerLine += line.trimAscii()
      } else {
         throw MailContentParseException("Invalid header line", line)
      }
   }
   parseHeader()
   // fix
   // "=?{charset}?{encoding}?{encoded_text}?="
   subject = processSubject(subject)
   
   if (contentId.startsWith("<") && contentId.endsWith(">")) {
      contentId = contentId[1..contentId.size-1]
   }
   // todo ?q? quopri
   // parse mime
   if (contentType == "") {
      return (from, to, cc, bcc, subject, content)
   }
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
      if (onlyHeaders) {
         return (from, to, cc, bcc, subject, MimeText("", contentTypeMime))
      }
      var textBody = ""
      while(let Some(line) <- lines.next()) {
            textBody += line + "\r\n"
      }
      if ("base64" == contentTransferEncoding) {
            textBody = String.fromUtf8(parseBase64MailContent(textBody))
      } else if ("quoted-printable" == contentTransferEncoding) {
            textBody = String.fromUtf8(parseQuotedPrintableMailContent(textBody))
      }
      let text = MimeText(textBody, contentTypeMime)
      return (from, to, cc, bcc, subject, textBody)
   } else if (contentTypeMime.startsWith("multipart/")) {
      let mimeMutilParts = MimeMutilParts()
      mimeMutilParts.contentType = contentTypeMime
      mimeMutilParts.contentId = contentId
      mimeMutilParts.headers = headers
      if (onlyHeaders) {
         return (from, to, cc, bcc, subject, mimeMutilParts)
      }
      if (boundary == "") {
            throw MailContentParseException("multipart missing boundary", contentType)
      }
      var line =  lines.next().getOrThrow({=>MailContentParseException("The email content ended prematurely")})
      while (!line.startsWith("--${boundary}")) {
            line = lines.next().getOrThrow({=>MailContentParseException("The email content ended prematurely not found boundary")})
      }
      // blank content
      if (line == "--${boundary}--") {
            return (from, to,  cc, bcc, subject, mimeMutilParts)
      }
      // children
      var builder = StringBuilder()
      while(true) {
            line = lines.next().getOrThrow({=> MailContentParseException("The email content ended prematurely")})
            if (line.startsWith("--${boundary}")) {
               let (_, _, _, _, _, data) = parseMailContent(builder.toString(), isPartEntry: true)
               mimeMutilParts.append(data)
               if (line == "--${boundary}--") {
                  break
               }
               builder = StringBuilder()
               continue
            }
            builder.append(line)
            builder.append("\r\n")
      }
      return (from, to,  cc, bcc, subject, mimeMutilParts)
   } else if (contentType == ""){
      return (from, to, cc, bcc, subject, content)
   } else {
      if (onlyHeaders) {
         return (from, to, cc, bcc, subject, MimeFile("".toArray(), contentTypeMime))
      }
      var textBody = ""
      while(let Some(line) <- lines.next()) {
            textBody += line + "\r\n"
      }
      let file = if ("base64" == contentTransferEncoding) {
            MimeFile(parseBase64MailContent(textBody), contentTypeMime)
      } else {
            MimeFile(textBody.toArray(), contentTypeMime)
      }
      file.headers = headers
      file.contentId = contentId
      return (from, to, cc, bcc, subject, file)
   }
}

public func parseBase64MailContent(content: String): Array<Byte> {
   fromBase64String(content.trimAscii().replace("\r\n", "")).getOrThrow({=>MailContentParseException("Invalid base64 content", content)})
}

public func parseQuotedPrintableMailContent(content: String): Array<Byte> {
   let builder = ByteArrayStream()
   let reader = StringReader(ByteArrayStream.fromString(content.trimAscii()))
   while(let Some(rune) <- reader.read()) {
      if (rune == r'=') {
         let next =String([
            reader.read().getOrThrow({=>MailContentParseException("Invalid quoted printable content", content)}),
            reader.read().getOrThrow({=>MailContentParseException("Invalid quoted printable content", content)})
         ])
         if (next == "\r\n") {
            continue
         }
         let byte = Byte.parse("0x${next}");
         builder.write([byte])
      } else {
         let bytes = String([rune]).toArray();
         builder.write(bytes)
      }
   }
   builder.bytes()
}

func processSubject(subjectInput: String): String {
   if (subjectInput == "") {
      return ""
   }
   var subject = subjectInput
   if (subject.startsWith("=?") && subject.endsWith("?=")) {
      let builder = StringBuilder()
      let sp = subject.split("\n")
      for (spItem in sp) {
         let item = spItem.trimAscii()
         if (item.toAsciiLower().startsWith("=?utf-8?b?") && item.endsWith("?=")) {
            let encoded = item[10..item.size-2]
            builder.append(String.fromUtf8(parseBase64MailContent(encoded)))
         } else if (item.toAsciiLower().startsWith("=?utf-8?q?") && item.endsWith("?=")) {
            let encoded = item[10..item.size-2]
            builder.append(String.fromUtf8(parseQuotedPrintableMailContent(encoded)))
         } else {
            builder.append(item)
         }
      }
      return builder.toString()
   } else {
      return subject
   }
}

