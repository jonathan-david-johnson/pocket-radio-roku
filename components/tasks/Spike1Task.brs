Sub init()
    m.top.functionName = "run"
End Sub

Sub run()
    lines = []
    lines.Push("Spike 1 — binary byte-fidelity")

    ' Build the canonical 256-byte sequence 0x00..0xFF.
    expected = CreateObject("roByteArray")
    for i = 0 to 255
        expected.Push(i)
    end for

    runResponseTest(lines)
    runRequestTest(lines, expected)

    rpt = Join(lines, Chr(10))
    print "========== SPIKE 1 REPORT =========="
    print rpt
    print "===================================="
    m.top.report = rpt
End Sub

' T1 — RESPONSE fidelity (the critical one).
' Fetch the same binary asset two ways:
'   (a) AsyncGetToFile -> roByteArray.ReadFile   (trusted reference)
'   (b) AsyncGetToString -> GetString -> FromAsciiString  (the POST-response path)
' If (b) != (a), reading binary POST responses on Roku is broken -> relay needed.
Sub runResponseTest(lines as object)
    url = "https://httpbin.org/image/png"

    ' (a) reference via file
    ref = CreateObject("roByteArray")
    p1 = CreateObject("roMessagePort")
    x1 = CreateObject("roUrlTransfer")
    x1.SetMessagePort(p1)
    x1.SetCertificatesFile("common:/certs/ca-bundle.crt")
    x1.InitClientCertificates()
    x1.SetUrl(url)
    okFile = false
    if x1.AsyncGetToFile("tmp:/spike1_ref.bin")
        m1 = wait(15000, p1)
        if type(m1) = "roUrlEvent" and m1.GetResponseCode() = 200
            ref.ReadFile("tmp:/spike1_ref.bin")
            okFile = true
        end if
    end if

    ' (b) test via string
    test = CreateObject("roByteArray")
    p2 = CreateObject("roMessagePort")
    x2 = CreateObject("roUrlTransfer")
    x2.SetMessagePort(p2)
    x2.SetCertificatesFile("common:/certs/ca-bundle.crt")
    x2.InitClientCertificates()
    x2.SetUrl(url)
    okStr = false
    if x2.AsyncGetToString()
        m2 = wait(15000, p2)
        if type(m2) = "roUrlEvent" and m2.GetResponseCode() = 200
            s = m2.GetString()
            test.FromAsciiString(s)
            okStr = true
        end if
    end if

    if not okFile or not okStr
        lines.Push("T1 RESPONSE: INCONCLUSIVE (fetch failed file=" + okFile.ToStr() + " str=" + okStr.ToStr() + ")")
        return
    end if

    lines.Push("T1 lengths: file=" + ref.Count().ToStr() + " str=" + test.Count().ToStr())
    cmp = compareBytes(ref, test)
    if cmp = -1
        lines.Push("T1 RESPONSE (GetString binary): PASS — bytes identical")
    else
        lines.Push("T1 RESPONSE (GetString binary): FAIL — first diff at byte " + cmp.ToStr())
        if cmp < ref.Count() and cmp < test.Count()
            lines.Push("    ref=0x" + decToHex(ref[cmp]) + " got=0x" + decToHex(test[cmp]))
        end if
    end if
End Sub

' T2 — REQUEST fidelity: POST 256 bytes from file, httpbin echoes them base64.
Sub runRequestTest(lines as object, expected as object)
    expected.WriteFile("tmp:/spike1_req.bin")

    p = CreateObject("roMessagePort")
    x = CreateObject("roUrlTransfer")
    x.SetMessagePort(p)
    x.SetCertificatesFile("common:/certs/ca-bundle.crt")
    x.InitClientCertificates()
    x.SetUrl("https://httpbin.org/post")
    x.AddHeader("Content-Type", "application/octet-stream")
    x.SetRequest("POST")

    if not x.AsyncPostFromFile("tmp:/spike1_req.bin")
        lines.Push("T2 REQUEST: INCONCLUSIVE (post failed to start)")
        return
    end if
    msg = wait(15000, p)
    if type(msg) <> "roUrlEvent" or msg.GetResponseCode() <> 200
        lines.Push("T2 REQUEST: INCONCLUSIVE (no 200 response)")
        return
    end if

    j = ParseJSON(msg.GetString())
    if j = invalid or j.data = invalid
        lines.Push("T2 REQUEST: INCONCLUSIVE (no data field)")
        return
    end if

    data = j.data
    ' Binary bodies come back as a data URI: data:application/octet-stream;base64,XXXX
    idx = Instr(1, data, "base64,")
    if idx > 0
        b64 = Mid(data, idx + 7)
        got = CreateObject("roByteArray")
        got.FromBase64String(b64)
        lines.Push("T2 echoed length=" + got.Count().ToStr())
        cmp = compareBytes(expected, got)
        if cmp = -1
            lines.Push("T2 REQUEST (POST binary): PASS — round-tripped 256 bytes")
        else
            lines.Push("T2 REQUEST (POST binary): FAIL — first diff at byte " + cmp.ToStr())
        end if
    else
        ' httpbin returned the bytes inline (means high bytes survived as text)
        lines.Push("T2 REQUEST: data not base64-encoded; len=" + Len(data).ToStr() + " (inspect)")
    end if
End Sub

' Returns -1 if equal, else index of first difference (or first length overrun).
Function compareBytes(a as object, b as object) as integer
    if a.Count() <> b.Count() then return Min(a.Count(), b.Count())
    for i = 0 to a.Count() - 1
        if a[i] <> b[i] then return i
    end for
    return -1
End Function

Function Min(x as integer, y as integer) as integer
    if x < y then return x
    return y
End Function

Function decToHex(n as integer) as string
    h = "0123456789ABCDEF"
    return Mid(h, (n \ 16) + 1, 1) + Mid(h, (n mod 16) + 1, 1)
End Function

Function Join(arr as object, sep as string) as string
    out = ""
    for i = 0 to arr.Count() - 1
        if i > 0 then out = out + sep
        out = out + arr[i]
    end for
    return out
End Function
