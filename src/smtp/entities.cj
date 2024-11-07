
package cj_mail.smtp

import cj_lombok.*
import cj_mail.commons.*

@Default
@ToString
public class SmtpResponse {
   public var code: Int64
   public var message: String
}

@AllArgsConstructor
@ToString
public class SmtpException <: MailException {
   public var serverResponse: SmtpResponse
}
