Sub init()
    m.title = m.top.findNode("title")
    m.status = m.top.findNode("status")
    m.mode = "boot"
    m.top.setFocus(true)

    auth = AuthRead()
    if auth <> invalid and auth.token <> ""
        showMain(auth)
    else
        promptEmail()
    end if
End Sub

' ---- login flow (two-step keyboard, dev-prefilled) -------------------------

Sub promptEmail()
    m.mode = "login_email"
    m.expectingEmailButton = true
    dlg = CreateObject("roSGNode", "KeyboardDialog")
    dlg.title = "Pocket Casts Email"
    dlg.text = TestEmail()   ' dev prefill; real users edit via keyboard
    dlg.buttons = ["Next", "Cancel"]
    m.dlg = dlg
    dlg.observeField("buttonSelected", "onEmailBtn")
    m.top.dialog = dlg
End Sub

Sub onEmailBtn()
    if not m.expectingEmailButton then return
    m.expectingEmailButton = false
    if m.dlg.buttonSelected = 0
        m.email = m.dlg.text
        closeDialog()
        promptPassword()
    else
        closeDialog()
        m.status.text = "Login cancelled."
        promptEmail()
    end if
End Sub

Sub promptPassword()
    m.mode = "login_password"
    m.expectingPasswordButton = true
    dlg = CreateObject("roSGNode", "KeyboardDialog")
    dlg.title = "Pocket Casts Password"
    dlg.text = TestPassword()
    dlg.buttons = ["Log In", "Back"]
    m.dlg = dlg
    dlg.observeField("buttonSelected", "onPasswordBtn")
    m.top.dialog = dlg
End Sub

Sub onPasswordBtn()
    if not m.expectingPasswordButton then return
    m.expectingPasswordButton = false
    if m.dlg.buttonSelected = 0
        m.password = m.dlg.text
        closeDialog()
        doLogin()
    else
        closeDialog()
        promptEmail()
    end if
End Sub

Sub closeDialog()
    if m.dlg <> invalid then m.dlg.close = true
    m.top.dialog = invalid
    m.dlg = invalid
End Sub

Sub doLogin()
    m.status.text = "Logging in..."
    m.relay = CreateObject("roSGNode", "RelayTask")
    m.relay.observeField("response", "onLoginResp")
    m.relay.bodyJson = FormatJSON({ action: "login", email: m.email, password: m.password })
    m.relay.control = "RUN"
End Sub

Sub onLoginResp()
    code = m.relay.status
    if code = 401 or code = 403
        AuthClear()
        m.status.text = "Invalid credentials. Try again."
        promptPassword()
        return
    end if
    if code <> 200
        m.status.text = "Login failed (" + code.ToStr() + "). Check network and try again."
        promptEmail()
        return
    end if
    data = ParseJSON(m.relay.response)
    if data = invalid or data.token = invalid or data.token = ""
        m.status.text = "Login failed (bad response). Try again."
        promptEmail()
        return
    end if
    if data.userId = invalid or data.userId = "" or data.email = invalid or data.email = ""
        m.status.text = "Login failed (incomplete user data). Try again."
        promptEmail()
        return
    end if
    AuthWrite(data.token, data.userId, data.email)
    showMain({ token: data.token, userid: data.userId, email: data.email })
End Sub

' ---- main (logged-in) ------------------------------------------------------

Sub showMain(auth as object)
    m.mode = "main"
    m.auth = auth
    m.top.setFocus(true)
    m.title.text = "PocketStreams"
    m.status.text = "Logged in as " + auth.email + Chr(10) + "OK = play/pause KCRW    Back = log out"

    if m.audio = invalid
        m.audio = m.top.createChild("Audio")
        content = createObject("roSGNode", "ContentNode")
        content.url = "https://streams.kcrw.com/e24_mp3"
        content.streamformat = "mp3"
        m.audio.content = content
        m.audio.observeField("state", "onAudioState")
    end if
    m.audio.control = "play"
End Sub

Sub logout()
    if m.audio <> invalid then m.audio.control = "stop"
    AuthClear()
    m.auth = invalid
    m.top.dialog = invalid
    m.title.text = "PocketStreams — M2"
    m.status.text = "Logged out."
    promptEmail()
End Sub

Sub onAudioState()
    if m.mode <> "main" then return
End Sub

Function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    if m.mode <> "main" then return false
    if key = "back"
        logout()
        return true
    else if key = "OK" or key = "play"
        if m.audio.state = "playing"
            m.audio.control = "pause"
        else
            m.audio.control = "resume"
        end if
        return true
    end if
    return false
End Function
