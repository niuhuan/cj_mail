
package cj_mail.smtp

@Default
@ToString
public class SmtpResponse {
   public var code: Int64
   public var message: String
}

@AllArgsConstructor
@ToString
public class SmtpException <: Exception {
   public var serverResponse: ServerResponse
}
