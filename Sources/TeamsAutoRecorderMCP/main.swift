// Sources/TeamsAutoRecorderMCP/main.swift
//
// TeamsAutoRecorder MCP ヘルパー CLI
// Claude Code が stdio 経由で MCP サーバーに接続するためのブリッジ。
// stdin/stdout ↔ TeamsAutoRecorder.app の unix socket を中継するだけ。
//
// Claude Code 設定例:
//   {
//     "type": "stdio",
//     "command": "/path/to/TeamsAutoRecorderMCP"
//   }

#if canImport(Darwin)
    import Darwin
#endif
import Foundation

let socketPath = "/tmp/teams-auto-recorder-mcp.sock"

let sockFd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
guard sockFd >= 0 else {
    fputs("error: ソケットの作成に失敗しました\n", stderr)
    exit(1)
}

var addr = sockaddr_un()
addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
addr.sun_family = sa_family_t(AF_UNIX)
socketPath.withCString { src in
    withUnsafeMutablePointer(to: &addr.sun_path) { dest in
        dest.withMemoryRebound(to: CChar.self, capacity: 104) {
            _ = strncpy($0, src, 103)
        }
    }
}

let connectResult = withUnsafePointer(to: addr) { ptr in
    ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        Darwin.connect(sockFd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
    }
}

guard connectResult == 0 else {
    fputs("error: TeamsAutoRecorder の MCP サーバーに接続できません (\(socketPath))\n", stderr)
    fputs("TeamsAutoRecorder が起動していて MCP サーバーが有効になっているか確認してください。\n", stderr)
    exit(1)
}

func forward(from src: Int32, to dst: Int32) {
    let bufSize = 4096
    var buf = [UInt8](repeating: 0, count: bufSize)
    while true {
        let n = Darwin.read(src, &buf, bufSize)
        guard n > 0 else { break }
        var offset = 0
        while offset < n {
            let w = Darwin.write(dst, Array(buf[offset..<n]), n - offset)
            guard w > 0 else { return }
            offset += w
        }
    }
}

let done = DispatchSemaphore(value: 0)

// stdin → socket
DispatchQueue.global().async {
    forward(from: STDIN_FILENO, to: sockFd)
    Darwin.shutdown(sockFd, SHUT_WR)
    done.signal()
}

// socket → stdout
DispatchQueue.global().async {
    forward(from: sockFd, to: STDOUT_FILENO)
    done.signal()
}

// どちらかのストリームが閉じたら終了
done.wait()
Darwin.close(sockFd)
exit(0)
