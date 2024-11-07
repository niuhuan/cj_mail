package cj_mail.commons

import std.collection.*
import std.socket.*
import std.io.*
import net.tls.*

import cj_lombok.*

public class MailConnection {
    var socket: StreamingSocket
    var reader: StringReader<IOStream>
    var writer: StringWriter<IOStream>

    public init(socket: StreamingSocket) {
        this.socket = socket
        this.reader = StringReader(socket)
        this.writer = StringWriter(socket)
    }

    public func disconnect() {
        socket.close()
    }

    public func write(content: String) {
        writer.write(content)
    }

    public func flush() {
        writer.flush()
    }

    public func readln(): ?String {
        reader.readln()
    }
}
