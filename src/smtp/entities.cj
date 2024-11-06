
package cj_mail.smtp

import cj_lombok.*
import cj_mail.commons.*

@Default
@AllArgsConstructor
public class SendMail {
   public var mailFrom: MailAddress
   public var rcptTo: Array<MailAddress>
   public var subject: String
   public var data: MailContent = ""
}

@Default
@ToString
public class SmtpResponse {
   public var code: Int64
   public var message: String
}

@AllArgsConstructor
@ToString
public class SmtpException <: Exception {
   public var serverResponse: SmtpResponse
}
