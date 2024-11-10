package cj_mail.commons

import std.collection.*
import std.socket.*
import std.io.*
import net.tls.*

import cj_lombok.*

public class MailConnection {

    public var socket: StreamingSocket
    public var reader: StreamReader 

    public init(socket: StreamingSocket) {
        this.socket = socket
        this.reader = StreamReader(socket)
    }

    public func disconnect() {
        socket.close()
    }

    public func write(content: String) {
        socket.write(content.toArray())
    }

    public func flush() {
        socket.flush()
    }

}


public class StreamReader {
    
    var readBuff = Array<Byte>(8192, {_=>0})
    var writeToBuffPosition = 0
    var readToBuffPosition = 0

    var socket: InputStream

    public init(socket: InputStream) {
        this.socket = socket
    }

    public func readln(): ?String {
        let builder = ArrayList<Byte>()
        while (true) {
            let idx = readBuff[readToBuffPosition..writeToBuffPosition].indexOf("\n".toArray()[0])
            match (idx) {
                case Some(idx) =>
                    builder.appendAll(readBuff[readToBuffPosition..(readToBuffPosition + idx + 1)])
                    readToBuffPosition = readToBuffPosition + idx + 1
                    var i = 0
                    while (readToBuffPosition < writeToBuffPosition) {
                        readBuff[i] = readBuff[readToBuffPosition]
                        readToBuffPosition += 1
                        i += 1
                    }
                    writeToBuffPosition = i
                    readToBuffPosition = 0
                    let str = String.fromUtf8(builder.toArray()).trimRight("\n").trimRight("\r")
                    return str
                case None =>
                    builder.appendAll(readBuff[readToBuffPosition..writeToBuffPosition])
                    readToBuffPosition = 0
                    writeToBuffPosition = socket.read(readBuff)
                    if (writeToBuffPosition == 0) {
                        if (builder.size == 0) {
                            return Option<String>.None
                        } else {
                            return builder.toString()
                        }
                    }
                    continue
            }
        }
        throw Exception("unreachable")
    }

    public func readByte(): ?Byte {
        while (true) {
            if (readToBuffPosition < writeToBuffPosition) {
                readToBuffPosition++
                return readBuff[readToBuffPosition - 1]
            } else if (readToBuffPosition == writeToBuffPosition) {
                readToBuffPosition = 0
                writeToBuffPosition = socket.read(readBuff)
                if (writeToBuffPosition == 0) {
                    return Option<Byte>.None
                }
            } else {
                throw Exception("readToBuffPosition > writeToBuffPosition")
            }
        }
        throw Exception("unreachable")
    }


    public func readSize(size: Int): Array<Byte> {
        if (size == 0) {
            return Array<Byte>(0, {_=>0})
        }
        let array = Array<Byte>(size, {_=>0})
        for (i in 0..size) {
            array[i] = this.readByte().getOrThrow({=>MailContentParseException("eof")})
        }
        array
    }

    public func readUntil(predicate: (Rune)->Bool) : ?String {
        let str = StringBuilder();
        while(true) {
            match (readRune()) {
                case Some(rune) =>
                    str.append(rune)
                    if (predicate(rune)) {
                        break
                    }
                case None =>
                    break
            }
        }
        if (str.size == 0) {
            return None
        } 
        str.toString()
    }

    public func readRune(): ?Rune {
        let builder = ArrayList<Byte>()
        let readByte = match (this.readByte()) {
            case Some(b) => b
            case None => return None
        }
        builder.append(readByte)
        //  # 0xxxxxxx  # 110xxxxx  # 1110xxxx # 11110xxx
        if ((readByte & 0b10000000) == 0) {
            //
        } else if ((readByte & 0b11100000) == 0b11000000) {
            builder.append(this.readByte().getOrThrow({=>MailContentParseException("eof")}))
        } else if ((readByte & 0b11110000) == 0b11100000) {
            builder.append(this.readByte().getOrThrow({=>MailContentParseException("eof")}))
            builder.append(this.readByte().getOrThrow({=>MailContentParseException("eof")}))
        } else if ((readByte & 0b11111000) == 0b11110000) {
            builder.append(this.readByte().getOrThrow({=>MailContentParseException("eof")}))
            builder.append(this.readByte().getOrThrow({=>MailContentParseException("eof")}))
            builder.append(this.readByte().getOrThrow({=>MailContentParseException("eof")}))
        } else {
            throw MailContentParseException("invalid utf8")
        }
        let ra = String.fromUtf8(builder.toArray()).toRuneArray()
        if (ra.size > 1) {
            throw MailContentParseException("invalid utf8")
        }
        ra[0]
    }

}

public func defaultTlsConnect(host: String, port: UInt16): MailConnection {
      let socket = TcpSocket(host, port)
      socket.connect()
      let tls = try {
        var config = TlsClientConfig()
        config.verifyMode = TrustAll
        config.alpnProtocolsList = ["h2"]
        TlsSocket.client(socket, clientConfig: config)
      } catch (e: Exception) {
        socket.close()
        throw e
      }
      try {
          tls.handshake()
      }catch (e: Exception) {
        tls.close()
        throw e
      }
      MailConnection(tls)
}

public func mailConnection(socket: StreamingSocket) {
    MailConnection(socket)
}
