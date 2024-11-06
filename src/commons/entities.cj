package cj_mail.commons

import std.collection.*
import std.regex.*
import cj_lombok.*

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
   public func toString() {
      let dataString = if (let Some(str) <- data as String) {
         str
      } else if (let Some(str) <- data as MimeText) {
         str.text
      } else if (let Some(file) <- data as MutilPartContent) {
         var str = "["
         for (part in file) {
            if (let Some(text) <- part as MimeText) {
               str += "MimeText(contentType=${text.contentType}, size=${text.text.size})"
            } else if (let Some(file) <- part as MimeFile) {
               str += "MimeFile(contentType=${file.contentType}, size=${file.data.size})"
            }
         }
         str += "]"
         str
      } else {
         "Unknown"
      }
      "Mail(mailFrom=${mailFrom}, rcptTo=${rcptTo}, subject=${subject}, data=${dataString})"
   }
}

public type SendMail = Mail
public type ReceiveMail = Mail

public interface MailContent {
}

public interface MutilPart {
}

extend String <: MailContent  & MutilPart{
}

/*
Content-Type: text/html; charset="utf-8"
MIME-Version: 1.0
Content-Transfer-Encoding: base64

aGVsbG8sIHNlbmQgYnkgUHl0aG9uLi4u
*/
@Default
public class MimeText <: MailContent & MutilPart {
     public var text: String = ""
     public var contentType: String = ""

     public init(text: String, contentType: String) {
        this.text = text
        this.contentType = contentType
     }
}


@Default
public class MimeFile <: MutilPart {
     public var data: Array<Byte> = []
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

extend ArrayList<MutilPart> <: MailContent {
}

public type MutilPartContent = ArrayList<MutilPart>
