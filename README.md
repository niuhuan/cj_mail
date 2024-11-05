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

- [x] SMTP
    - [x] 基础认证
    - [x] LOGIN认证
    - [x] 发送文本/html邮件
    - [x] 发送附件

## 🔖 用例

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
   // smtp.quit() // 我的服务器不支持quit命令, 所以将quit和close分开
   smtp.close()
   return 0
}

func textMail(): SendMail {
   let mail = SendMail()
   mail.mailFrom.name = "niuhuan"
   mail.mailFrom.address = "niuhuan@mail.com"
   mail.rcptTo = [MailAddress("niuhuan", "niuhuan@mail.com")]
   mail.data = "Hello, World!"
   // mail.data = MimeText("<h1>Hello, World!</h1>","text/html") // html渲染
   mail
}

// 多分段带附件的邮件
func mutilPartsMail(): SendMail {
   let mail = SendMail()
   mail.mailFrom.name = "niuhuan"
   mail.mailFrom.address = "niuhuan@mail.com"
   mail.rcptTo = [MailAddress("niuhuan", "niuhuan@mail.com")]
   let content = ArrayList<MutilPart>()
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

## 🏆 贡献

欢迎您的issue和pull request, fork时请保留源仓库地址

#### 计划中的特性

- [ ] POP/IMAP

## 📕 协议

参考 [LICENSE](LICENSE) 文件

