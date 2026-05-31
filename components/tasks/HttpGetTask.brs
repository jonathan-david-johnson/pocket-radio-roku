Sub init()
    m.top.functionName = "execGet"
End Sub

' Runs on the Task thread. Blocking roUrlTransfer is fine here.
Sub execGet()
    url = m.top.url
    print "[HttpGetTask] GET "; url

    port = CreateObject("roMessagePort")
    xfer = CreateObject("roUrlTransfer")
    xfer.SetMessagePort(port)
    xfer.SetUrl(url)
    xfer.SetCertificatesFile("common:/certs/ca-bundle.crt")
    xfer.InitClientCertificates()
    xfer.AddHeader("User-Agent", m.top.userAgent)
    xfer.EnableEncodings(true)

    if xfer.AsyncGetToString()
        msg = wait(15000, port)
        if type(msg) = "roUrlEvent"
            code = msg.GetResponseCode()
            body = msg.GetString()
            print "[HttpGetTask] status="; code; " bytes="; Len(body)
            m.top.status = code
            m.top.response = body
        else
            print "[HttpGetTask] timeout / no response"
            m.top.status = -1
            m.top.response = ""
        end if
    else
        print "[HttpGetTask] AsyncGetToString failed to start"
        m.top.status = -2
        m.top.response = ""
    end if
End Sub
