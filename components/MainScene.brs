Sub init()
    print "[MainScene] init"
    m.title = m.top.findNode("title")
    m.status = m.top.findNode("status")

    ' Relay spike: prove Roku -> pc-relay (JSON) -> Pocket Casts (protobuf) -> JSON.
    m.stage = "login"
    m.status.text = "Logging in via relay..."
    callRelay({ action: "login", email: TestEmail(), password: TestPassword() })
End Sub

' Fresh Task node per call — re-running one node from inside its own observer
' does not refire reliably in SceneGraph.
Sub callRelay(req as object)
    m.relay = CreateObject("roSGNode", "RelayTask")
    m.relay.observeField("response", "onRelay")
    m.relay.bodyJson = FormatJSON(req)
    m.relay.control = "RUN"
End Sub

Sub onRelay()
    code = m.relay.status
    body = m.relay.response
    print "[MainScene] onRelay stage="; m.stage; " status="; code

    if code <> 200
        m.status.text = "Relay error (" + code.ToStr() + "): " + Left(body, 200)
        return
    end if
    data = ParseJSON(body)
    if data = invalid
        m.status.text = "Bad JSON from relay"
        return
    end if

    if m.stage = "login"
        m.token = data.token
        print "[MainScene] token len="; Len(m.token); " userId="; data.userId
        m.status.text = "Logged in. Fetching Up Next..."
        m.stage = "upNext"
        callRelay({ action: "upNext", token: m.token, deviceId: CreateObject("roDeviceInfo").GetChannelClientId() })
    else if m.stage = "upNext"
        eps = data.episodes
        lines = ["Relay OK — Up Next (" + eps.Count().ToStr() + "):"]
        for i = 0 to eps.Count() - 1
            if i >= 6 then exit for
            ep = eps[i]
            lines.Push("- " + ep.title)
            print "[MainScene] ep: "; ep.title
        end for
        m.status.text = Join(lines, Chr(10))
    end if
End Sub

Function Join(arr as object, sep as string) as string
    out = ""
    for i = 0 to arr.Count() - 1
        if i > 0 then out = out + sep
        out = out + arr[i]
    end for
    return out
End Function
