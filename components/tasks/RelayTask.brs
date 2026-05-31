Sub init()
    m.top.functionName = "execPost"
End Sub

Sub execPost()
    body = m.top.bodyJson
    port = CreateObject("roMessagePort")
    xfer = CreateObject("roUrlTransfer")
    xfer.SetMessagePort(port)
    xfer.SetUrl(RelayUrl())
    xfer.SetCertificatesFile("common:/certs/ca-bundle.crt")
    xfer.InitClientCertificates()
    xfer.AddHeader("Content-Type", "application/json")
    xfer.AddHeader("x-relay-secret", RelaySecret())
    xfer.SetRequest("POST")

    print "[RelayTask] POST "; Len(body); " bytes"
    if xfer.AsyncPostFromString(body)
        msg = wait(20000, port)
        if type(msg) = "roUrlEvent"
            m.top.status = msg.GetResponseCode()
            m.top.response = msg.GetString()
            print "[RelayTask] status="; m.top.status; " resp bytes="; Len(m.top.response)
        else
            print "[RelayTask] timeout"
            m.top.status = -1
            m.top.response = ""
        end if
    else
        print "[RelayTask] post failed to start"
        m.top.status = -2
        m.top.response = ""
    end if
End Sub
