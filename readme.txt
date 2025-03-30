==================
smtp-onebot-bridge
==================

提供一个 smtp 服务器，发送到这儿的邮件会被自动转发到 onebot

----------
安装依赖项
----------

如果是 debian：

    apt install libhttp-tiny-perl libjson-perl libnet-smtp-server-perl

别的不会了。如果能用 cpan 的话：

    cpan HTTP::Tiny JSON Net::SMTP::Server

--------
配置选项
--------

通过环境变量配置程序功能

* LISTEN_ADDRESS: SMTP 服务器监听地址，比如 127.0.0.1
* LISTEN_PORT: SMTP 服务器监听端口，比如 2525
* ONEBOT_API: onebot 服务的地址，比如 http://192.168.1.114:14283
* ONEBOT_TOKEN: onebot 服务的鉴权 token，可选

----
运行
----

    perl main.pl

----------
收件人说明
----------

在一封由 aa@bb 发往 cc@dd 的邮件里，程序会依次检查 cc、dd、aa、bb，并且从中寻找满足格式要求的条目。选择第一个作为发送对象。

具体来说有三种格式:

* q_<number>: 向号码为 <number> 的好友发送私聊消息
* g_<group_id>: 向号码为 <group_id> 的群组发送消息
* m_<number>_<group_id>: 在号码为 <group_id> 的群组内发送消息，并且 at 号码为 <number> 的成员

------
使用例
------

使用 swaks：

    swaks -t p_114514@aahahaha.io --server 127.0.0.1 --port 2525 --header 'Subject: 呜喵呜喵可爱喵' --body '嘻嘻'

会向 QQ 号为 114514 的好友发送私聊消息，排版如下：

    【呜喵呜喵可爱喵】
    <jyi@reggie.>

    嘻嘻
