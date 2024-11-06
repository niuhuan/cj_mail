
package cj_mail.pop

import net.tls.*
import std.socket.*
import std.io.*

public class Pop {
    public var host: String =  ""
    public var tlsPort: UInt16 = 995

    private var lastSession: ?TlsSession = None
    private var tlsTlsSocket: ?TlsSocket = None
    private var reader: ?StringReader<IOStream> = None
    private var writer: ?StringWriter<IOStream> = None

   public func connect() {
      // init tls
      let socket = TcpSocket(host, tlsPort)
      socket.connect()
      var config = TlsClientConfig()
      config.verifyMode = TrustAll
      config.alpnProtocolsList = ["h2"]
      let tls = TlsSocket.client(socket, clientConfig: config, session: lastSession)
      this.tlsTlsSocket = Some(tls)
      tls.handshake()
      lastSession = tls.session
      reader = StringReader(tls)
      writer = StringWriter(tls)
      readAll()
   }

    public func readAll() {
        let reader = this.reader.getOrThrow()
        while (true) {
            let line = reader.readln().getOrThrow()
            println("line: ${line})")
        }
    }
}