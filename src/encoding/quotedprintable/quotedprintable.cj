package cj_mail.encoding.quotedprintable

import std.io.*

import cj_mail.exception.*


let exclamationMark = "!".toArray()[0]
let tilde = "~".toArray()[0]
let equals = "=".toArray()[0]
let translationNewLine = "\n".toArray()[0]
let translationRreturn = "\r".toArray()[0]

let space = " ".toArray()[0]
let tab = "\t".toArray()[0]

const lineMaxLen = 76
let upperhex = "0123456789ABCDEF".toArray()

public let StdQuotedPrintable = QuotedPrintable()

public class QuotedPrintable {

    public func encoder(): QuotedPrintableEncoder {
        QuotedPrintableEncoder()
    }

    public func decoder(): QuotedPrintableDecoder {
        QuotedPrintableDecoder()
    }

    public func encodeToString(data: Array<Byte>): String {
        let buffStream = ByteArrayStream()
        let qpoStream = QuotedPrintableOutputStream(buffStream)
        qpoStream.write(data)
        qpoStream.flushLine()
        qpoStream.flush()
        String.fromUtf8(buffStream.readToEnd())
    }
}

public class QuotedPrintableEncoder {
    
    let buffStream = ByteArrayStream()
    let qpoStream = QuotedPrintableOutputStream(buffStream)
    private var isFinished = false

    public prop finished: Bool {
        get () { isFinished }
    }

    protected init() {
    }

    public func encode(data: Array<Byte>, finish!: Bool = false): Array<Byte> {
        if (isFinished) {
            throw MailContentParseException("Encoder has isFinished")
        }
        qpoStream.write(data)
        if (finish) {
            qpoStream.flushLine()
            isFinished = true
        }
        qpoStream.flush()
        let result = buffStream.readToEnd()
        buffStream.clear()
        result
    }

    public func finish(): Array<Byte> {
        encode([], finish: true)
    }

}

public class QuotedPrintableDecoder {
    protected init() {
    }
}

private func isWhitespace(b: Byte): Bool {
    b == space || b == tab
}

public class QuotedPrintableOutputStream <: OutputStream {

    private let output: OutputStream
    private var cr = false
	private let line = Array<Byte>(78, {_=>0})
    private var i = 0

    protected init(output: OutputStream) {
        this.output = output
    }

    public func write(p: Array<Byte>): Unit {
        writeData(p)
    }

    public func flush() {
        output.flush()
    }

    public func writeData(p: Array<Byte>): Int64 {
        var n = 0
        for (i in 0..p.size) {
            let b = p[i]
            if (b >= exclamationMark && b <= tilde && b != equals) {
                continue
            }
            if (isWhitespace(b)) {
                continue
            }
            if (i > n) {
                writeRaw(p[n..i])
                n = i
            }
            encode(b)
            n++
        }
        if (n == p.size) {
            return n
        }
        writeRaw(p[n..p.size])
        return p.size
    }

    private func writeRaw(p: Array<Byte>) {
        for (idx in 0..p.size) {
            let b = p[idx]
            if (b == translationNewLine || b == translationRreturn) {
                // If the previous byte was \r, the CRLF has already been inserted.
                if (cr && b == translationNewLine) {
                    cr = false
                    continue
                }

                if (b == translationRreturn) {
                    cr = true
                }

                checkLastByte()
                insertCRLF()

                continue
            }

            if (i == lineMaxLen-1) {
                insertSoftLineBreak()
            }

            line[i] = b
            this.i ++
            cr = false
        }
    }

    private func encode(b: Byte) {
        if (lineMaxLen - 1 - i < 3) {
		    insertSoftLineBreak()
	    }
        line[i] = equals
        line[i+1] = upperhex[Int64(b>>4)]
        line[i+2] = upperhex[Int64(b&0x0f)]
        i += 3
    }

    private func  checkLastByte()  {
        if (i == 0) {
            return
        }
        let b = line[i-1]
        if (isWhitespace(b)) {
            i--
            encode(b)
        }
    }

    private func insertSoftLineBreak() {
        line[i] = equals
        i++
        insertCRLF()
    }

    private func insertCRLF() {
        line[i] = translationRreturn
        line[i+1] = translationNewLine
        i += 2
        flushLine()
    }

    public func flushLine() {
        output.write(line[0..i])
        i = 0
    }

}

