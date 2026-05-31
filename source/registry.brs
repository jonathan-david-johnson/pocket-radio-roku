' Auth token persistence in roRegistrySection "auth". No Keychain on Roku.

Function AuthRead() as object
    sec = CreateObject("roRegistrySection", "auth")
    if not sec.Exists("token") then return invalid
    token = sec.Read("token")
    userid = sec.Read("userid")
    email = sec.Read("email")
    if token = invalid or token = "" then return invalid
    if userid = invalid then userid = ""
    if email = invalid then email = ""
    return {
        token: token,
        userid: userid,
        email: email
    }
End Function

Sub AuthWrite(token as string, userid as string, email as string)
    sec = CreateObject("roRegistrySection", "auth")
    if token = invalid then token = ""
    if userid = invalid then userid = ""
    if email = invalid then email = ""
    sec.Write("token", token)
    sec.Write("userid", userid)
    sec.Write("email", email)
    sec.Flush()
End Sub

Sub AuthClear()
    sec = CreateObject("roRegistrySection", "auth")
    sec.Delete("token")
    sec.Delete("userid")
    sec.Delete("email")
    sec.Flush()
End Sub

' Stable device identifier (per channel install). Used as deviceId for Up Next.
Function GetDeviceId() as string
    return CreateObject("roDeviceInfo").GetChannelClientId()
End Function
