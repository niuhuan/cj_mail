package cj_mail.commons

import std.collection.*

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
public struct MimeText <: MailContent & MutilPart {
     var text: String = ""
     var contentType: String = ""

     public init(text: String, contentType: String) {
        this.text = text
        this.contentType = contentType
     }
}


@Default
public struct MimeFile <: MutilPart {
     var data: Array<Byte> = []
     var contentType: String = ""
     var headers: ArrayList<(String, String)> = ArrayList()

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
