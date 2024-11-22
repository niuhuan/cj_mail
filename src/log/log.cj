package cj_mail.log

import log.*

protected var cjMailLogger = getGlobalLogger(("name", "cj_mail"))

public func setCjMailLogger(logger: Logger): Unit {
    cjMailLogger = logger
}
