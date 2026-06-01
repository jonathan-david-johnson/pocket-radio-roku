Sub init()
    m.top.functionName = "exec"
End Sub

Sub exec()
    method = m.top.method
    url = m.top.url
    body = m.top.body

    port = CreateObject("roMessagePort")
    xfer = CreateObject("roUrlTransfer")
    xfer.SetMessagePort(port)
    xfer.SetUrl(url)
    xfer.SetCertificatesFile("common:/certs/ca-bundle.crt")
    xfer.InitClientCertificates()

    if m.top.headers <> invalid
        for each key in m.top.headers
            xfer.AddHeader(key, m.top.headers[key])
        end for
    end if

    if method = "POST"
        xfer.SetRequest("POST")
        ok = xfer.AsyncPostFromString(body)
    else if method = "DELETE"
        xfer.SetRequest("DELETE")
        ok = xfer.AsyncPostFromString(body)
    else
        xfer.EnableEncodings(true)
        ok = xfer.AsyncGetToString()
    end if

    if ok
        msg = wait(20000, port)
        if type(msg) = "roUrlEvent"
            m.top.status = msg.GetResponseCode()
            m.top.response = msg.GetString()
        else
            m.top.status = -1
            m.top.response = ""
        end if
    else
        m.top.status = -2
        m.top.response = ""
    end if
End Sub