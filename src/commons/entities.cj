package cj_mail.commons

import std.collection.*
import std.regex.*
import cj_lombok.*
import encoding.base64.*
import log.*

let logger = getGlobalLogger(("cj_mail", "Parser"))

@Default
@AllArgsConstructor
public class MailAddress <: ToString {
   public var name: String
   public var address: String

   public func toString() {
      "${name}<${address}>"
   }
}

let mailAddressPattern = Regex("^(.*)?<(.*)>$")

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

@Default
@AllArgsConstructor
public class Mail {
   public var mailFrom: MailAddress
   public var rcptTo: ArrayList<MailAddress>
   public var subject: String
   public var data: MailContent = ""
}

extend Mail <: ToString {
   public func toString(): String {
      let builder = StringBuilder()
      append(builder, data)
      "Mail(mailFrom=${mailFrom}, rcptTo=${rcptTo}, subject=${subject}, data=${builder})"
   }

   private func append(builder: StringBuilder, data: MailContent): Unit {
      if (let Some(str) <- data as String) {
         builder.append(str)
      } else if (let Some(str) <- data as MimeText) {
         builder.append("MimeText(contentType=${str.contentType}, size=${str.text.size})")
      } else if (let Some(file) <- data as MimeFile) {
         builder.append("MimeFile(contentType=${file.contentType}, size=${file.data.size})")
      } else if (let Some(parts) <- data as MimeMutilParts) {
         builder.append("MimeMutilParts(contentType=${parts.contentType}, size=${parts.size}, parts=[")
         for (part in parts) {
            append(builder, part)
            builder.append(", ")
         }
         builder.append("])")
      } else {
         builder.append("Unknown")
      }
   }
}

public type SendMail = Mail
public type ReceiveMail = Mail

public interface MailContent {
}


extend String <: MailContent{
}

/*
Content-Type: text/html; charset="utf-8"
MIME-Version: 1.0
Content-Transfer-Encoding: base64

aGVsbG8sIHNlbmQgYnkgUHl0aG9uLi4u
*/
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
}


@Default
public class MimeFile <: MailContent {
     public var data: Array<Byte> = []
     public var contentId: String = ""
     public var contentType: String = ""
     public var headers: ArrayList<(String, String)> = ArrayList()

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
}


public func parseMailContent(content: String) : (String, String, String, MailContent) {
   var from = ""
   var to = ""
   var subject = ""
   var contentId = ""
   var contentType = ""
   var contentTransferEncoding =""
   var headers = ArrayList<(String, String)>()
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
            case "Content-Id" => contentId = value
            case "Content-Type" => contentType = value
            case "Content-Transfer-Encoding" => contentTransferEncoding = value
            case _ => 
                  headers.append((key, value))
      }
   }
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
            textBody = String.fromUtf8(fromBase64String(textBody.trimAscii().replace("\r\n", "")).getOrThrow())
      }
      return (from, to, subject, textBody)
   } else if (contentTypeMime.startsWith("multipart/")) {
      var line =  lines.next().getOrThrow()
      // first boundary
      if (!line.startsWith("--${boundary}")) {
            throw Exception("Invalid response : ${line}")
      }
      let mimeMutilParts = MimeMutilParts()
      mimeMutilParts.contentType = contentTypeMime
      mimeMutilParts.contentId = contentId
      mimeMutilParts.headers = headers
      // blank content
      if (line == "--${boundary}--") {
            return (from, to, subject, mimeMutilParts)
      }
      // children
      var builder = StringBuilder()
      while(true) {
            line = lines.next().getOrThrow()
            if (line.startsWith("--${boundary}")) {
               let (_, _, _, data) = parseMailContent(builder.toString())
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
      return (from, to, subject, mimeMutilParts)
   } else if (contentType == ""){
      return (from, to, subject, content)
   } else {
      var textBody = ""
      while(let Some(line) <- lines.next()) {
            textBody += line + "\r\n"
      }
      let file = if ("base64" == contentTransferEncoding) {
            MimeFile(fromBase64String(textBody.trimAscii().replace("\r\n", "")).getOrThrow(), contentTypeMime)
      } else {
            MimeFile(textBody.toArray(), contentTypeMime)
      }
      file.headers = headers
      file.contentId = contentId
      return (from, to, subject, file)
   }
}

