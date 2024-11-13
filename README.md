CJ_MAIL 仓颉邮件工具
=====================

仓颉编程语言 基础代码生成器。Java mail 的仓颉实现

## 📦 安装

使用git方式进行引入，并使用 `cjpm update` 进行更新

（当仓颉包管理器完善时，将会推送到仓库使用版本安装）

```yaml
[dependencies]

cj_mail = { git = "https://gitcode.com/niuhuan_cn/cj_mail.git" }
```


## 📖 特性

| 传输协议 | 详情 |
| -- | -- |
| SMTP | https://datatracker.ietf.org/doc/html/rfc5321 |
| POP | https://datatracker.ietf.org/doc/html/rfc1939 |
| IMAP | https://datatracker.ietf.org/doc/html/rfc3501 |
| SubTypes | https://www.w3.org/Protocols/rfc1341/7_2_Multipart.html |

- [x] SMTP
    - [x] 基础认证
    - [x] LOGIN认证
    - [x] 发送邮件
        - [x] 抄送 / 密送
        - [x] 发送文本/html邮件
        - [x] 发送附件
- [x] POP
    - [x] 基础认证
    - [x] `STAT` 获取邮件数
    - [x] `LIST` 列出邮件
    - [x] `RETR` 读取邮件
    - [x] `DELE` 删除邮件
    - [x] `retrParse` 获取邮件内容并解析
- [x] IMAP
    - [x] `LOGIN` 登录
    - [x] `SELECT` 获取收件箱邮件数量
    - [x] `SEARCH` 搜索邮件、返回UID列表
    - [x] `FETCH` 获取邮件内容
    - [x] `STORE` 增改标记（例如已读标记）
    - [x] `fetchParse` 获取邮件内容并解析
    - [x] `fetchInfo` 获取邮件内容并解析（不包含邮件正文）

## 🔖 用例

### SMTP

```cangjie
import cj_mail.*

main(): Int64 {
   // 连接邮件服务器并发送
   let smtp = Smtp()
   smtp.host = "smtp.mail.com"
   smtp.tlsPort = 465
   smtp.connect()
   smtp.plain("niuhuan@mail.com", "mailPassword")    // 基础认证
   // smtp.login("niuhuan@mail.com", "mailPassword") // LOGIN认证
   smtp.send(textMail())
   // smtp.quit() // 我的服务器不支持quit命令, 所以将quit和disconnect分开
   smtp.disconnect()
   return 0
}

func textMail(): SendMail {
   let mail = SendMail()
   mail.from.name = "niuhuan"
   mail.from.address = "niuhuan@mail.com"
   mail.to = [MailAddress("niuhuan", "niuhuan@mail.com")]
   mail.data = "Hello, World!"
   // mail.data = MimeText("<h1>Hello, World!</h1>","text/html") // html渲染
   mail
}

// 多分段带附件的邮件
func mutilPartsMail(): SendMail {
   let mail = SendMail()
   mail.from.name = "niuhuan"
   mail.from.address = "niuhuan@mail.com"
   mail.to = ArrayList([MailAddress("niuhuan", "niuhuan@mail.com")])
   let content = MimeMutilParts()
   // html 渲染邮件内容
   content.append(MimeText("<h1>Hello, World!</h1>","text/html")) 
   // 增加一个附件
   content.append(MimeFile(
    "Hello, World!".toArray(),
    "application/octet-stream",
    ArrayList<(String, String)>([("Content-Disposition", "attachment; filename=\"test.txt\"")])
   ))
   mail.data = content
   mail
}
```

### POP

```cangjie
main() : Int64{
    let pop = Pop()
    pop.host = "pop3.mail.com"  
    pop.tlsPort = 995
    pop.connect()  
    pop.auth("niuhuan@mail.com", "password")
    // let (邮件数量, ArrayList<(邮件编号,邮件大小)>) = pop.list()
    let(count, mails) = pop.list()  
    let mailIndex = mails[0][0]
    // 读取邮件内容, 并parse成mail对象, 使用参考 src/commons/entities.cj中的toStringQ
    let mail = pop.retrParse(mailIndex) 
    // 读取邮件内容 
    let(size,text) = pop.retr(mailIndex) 
    pop.quit()
    pop.disconnect()
    0
}
```

### IMAP

```cangjie
main(): Int64 {
    let imap = Imap()
    imap.host = "imap.mail.com"  
    imap.tlsPort = 993
    imap.connect()
    imap.login("niuhuan@mail.com", "password")
    imap.select("INBOX")
    // 查询邮件, 或者下载邮件
    let mails = imap.fetch("1:10", "FULL")
    // 下载邮件并解析
    let mails = imap.fetchParse("1:10")
    for ((uid, mail) in mails) { 
        println("uid : ${uid}, mail : ${mail}")
    }
    0
}
```

### 经过验证的仓颉版本

| 版本 | 分支 | 
| -- | -- |
| 0.53.13 | main |

## 🏆 贡献

欢迎您的issue和pull request, fork时请保留源仓库地址

#### 计划中的特性

- [ ] 附件输入流的方式读取

## 📕 协议

参考 [LICENSE](LICENSE) 文件

