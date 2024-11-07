package cj_mail.commons

import cj_lombok.*

public abstract class MailException <: Exception {
    public init() {
        super()
    }

    public init(message: String) {
        super(message)
    }
}

public class MailContentParseException <: MailException & ToString{

    private var _line: String = ""

    public prop line: String {
        get () {
            _line
        }
    }

    public init() {
        super()
    }

    public init(message: String) {
        super(message)
    }

    public init(message: String, line: String) {
        super(message)
        _line = line
    }

    public override func toString(): String {
        "MailContentParseException: ${message} (${line})"
    }
}

public class MailConnectExcption <: MailException & ToString {

    public init() {
        super()
    }

    public init(message: String) {
        super(message)
    }

    public override func toString(): String {
        "MailConnectExcption(${message})"
    }

}
