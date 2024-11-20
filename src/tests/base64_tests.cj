package cj_mail.tests

import log.*
import std.unittest.*
import std.unittest.testmacro.*

import cj_mail.*

@When[test]
const testText = "你好，世界！"
@When[test]
const testBase64 = "5L2g5aW977yM5LiW55WM77yB"

@When[test]
@Test
public class Base64Tests {
    let logger = getGlobalLogger(("name", "Base64Tests"))

    @TestCase
    func encodeToString(): Unit {
        logger.debug("Testing StdBase64 encodeToString")
        let encoded = StdBase64.encodeToString(testText.toArray())
        @Expect(encoded, testBase64) 
    }

    @TestCase
    func decodeFromString(): Unit {
        logger.debug("Testing StdBase64 decodeFromString")
        let decoded = StdBase64.decodeFromString(testBase64)
        let decodedText = String.fromUtf8(decoded);
        @Expect(decodedText, testText)
    }
}
