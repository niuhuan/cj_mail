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
