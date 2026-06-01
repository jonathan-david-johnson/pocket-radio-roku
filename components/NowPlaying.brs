Sub init()
    m.artwork      = m.top.findNode("artwork")
    m.title        = m.top.findNode("title")
    m.podcast      = m.top.findNode("podcast")
    m.liveLabel    = m.top.findNode("liveLabel")
    m.progressBg   = m.top.findNode("progressBg")
    m.progressFill = m.top.findNode("progressFill")
    m.timeLabel    = m.top.findNode("timeLabel")
    m.skipHint     = m.top.findNode("skipHint")
    m.bottomHint   = m.top.findNode("bottomHint")
End Sub

Sub onArtworkChanged()
    url = m.top.artworkUrl
    if url <> invalid and url <> ""
        m.artwork.uri = url
    else
        m.artwork.uri = ""
    end if
End Sub

Sub onDataChanged()
    m.title.text   = m.top.trackTitle
    m.podcast.text = m.top.podcastName

    isLive = m.top.isLive
    posVal = CInt(m.top.playPos)
    durVal = CInt(m.top.duration)

    m.liveLabel.visible    = isLive
    m.progressBg.visible   = not isLive
    m.progressFill.visible = not isLive
    m.timeLabel.visible    = not isLive
    m.skipHint.visible     = not isLive

    if isLive
        m.bottomHint.text = "Play/Pause  (Play btn)   |   Back  (Back)"
    else
        if durVal > 0
            frac = posVal / durVal
            if frac < 0.0 then frac = 0.0
            if frac > 1.0 then frac = 1.0
            fillW = Int(1220.0 * frac)
            m.progressFill.width = fillW
            leftSec = durVal - posVal
            m.timeLabel.text = NpFmt(posVal) + "  /  " + NpFmt(durVal) + "  (" + NpFmt(leftSec) + " left)"
        else
            m.progressFill.width = 0
            m.timeLabel.text = NpFmt(posVal)
        end if
        m.skipHint.text  = "<<  Back " + CInt(m.top.skipBack).ToStr() + "s      Fwd " + CInt(m.top.skipFwd).ToStr() + "s  >>"
        m.bottomHint.text = "Play/Pause  (Play btn)   |   Skip  (Left / Right / FF / REW)   |   Back  (Back)"
    end if
End Sub

Function NpFmt(secs as integer) as string
    h    = secs \ 3600
    mins = (secs Mod 3600) \ 60
    s    = secs Mod 60
    if h > 0
        return h.ToStr() + ":" + NpPad(mins) + ":" + NpPad(s)
    end if
    return mins.ToStr() + ":" + NpPad(s)
End Function

Function NpPad(n as integer) as string
    if n < 10 then return "0" + n.ToStr()
    return n.ToStr()
End Function
