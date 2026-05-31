Sub init()
    print "[MainScene] init"
    m.title = m.top.findNode("title")
    m.status = m.top.findNode("status")

    ' M1: play one hardcoded stream via the Audio node. OK / Play toggles.
    m.streamUrl = "https://streams.kcrw.com/e24_mp3"
    m.audio = m.top.createChild("Audio")
    content = createObject("roSGNode", "ContentNode")
    content.url = m.streamUrl
    content.streamformat = "mp3"   ' real inference (codec/URL) arrives in M3
    m.audio.content = content
    m.audio.observeField("state", "onAudioState")
    m.audio.control = "play"
    m.status.text = "Loading KCRW Eclectic 24..."

    m.top.setFocus(true)
End Sub

Sub onAudioState()
    st = m.audio.state
    print "[MainScene] audio state: "; st
    if st = "playing"
        m.status.text = "Playing — KCRW Eclectic 24 (OK to pause)"
    else if st = "paused"
        m.status.text = "Paused (OK to resume)"
    else if st = "buffering"
        m.status.text = "Buffering..."
    else if st = "error"
        m.status.text = "Playback error. See telnet 8085."
    else if st = "finished"
        m.status.text = "Stream ended."
    end if
End Sub

Function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    if key = "OK" or key = "play"
        if m.audio.state = "playing"
            m.audio.control = "pause"
        else
            m.audio.control = "resume"
        end if
        return true
    end if
    return false
End Function
