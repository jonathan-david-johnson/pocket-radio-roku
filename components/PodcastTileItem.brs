Sub init()
    m.focusBorder  = m.top.findNode("focusBorder")
    m.bg           = m.top.findNode("bg")
    m.art          = m.top.findNode("art")
    m.titleLabel   = m.top.findNode("titleLabel")
    m.podcastLabel = m.top.findNode("podcastLabel")
    m.timeLabel    = m.top.findNode("timeLabel")
    m.nowBg        = m.top.findNode("nowBg")
    m.nowLabel     = m.top.findNode("nowLabel")
End Sub

Sub onFocus()
    focused = m.top.focusPercent > 0.5
    if focused
        m.bg.color            = "0x1E333DFF"
        m.focusBorder.visible = true
    else
        m.bg.color            = "0x1A1B1DFF"
        m.focusBorder.visible = false
    end if
End Sub

Sub onContentSet()
    item = m.top.itemContent
    if item = invalid then return
    m.titleLabel.text = item.title
    if item.HDPosterUrl <> invalid and item.HDPosterUrl <> ""
        m.art.uri = item.HDPosterUrl
    else
        m.art.uri = ""
    end if
    meta = ParseJSON(item.description)
    if meta = invalid then return
    dateStr = meta.dateStr
    if dateStr <> invalid and dateStr <> ""
        m.podcastLabel.text = meta.podcastName + "  ·  " + dateStr
    else
        m.podcastLabel.text = meta.podcastName
    end if
    dur    = CInt(meta.duration)
    played = CInt(meta.playedUpTo)
    if played > 0
        left = dur - played
        m.timeLabel.text  = PodFmt(left) + " left"
        m.timeLabel.color = "0x00A0E8FF"
    else if dur > 0
        m.timeLabel.text  = PodFmt(dur)
        m.timeLabel.color = "0x9C9FA4FF"
    else
        m.timeLabel.text = ""
    end if
End Sub

Sub onNowPlayingChanged()
    playing = m.top.isNowPlaying
    m.nowBg.visible    = playing
    m.nowLabel.visible = playing
End Sub

Function PodFmt(secs as integer) as string
    if secs <= 0 then return "0m"
    h    = secs \ 3600
    mins = (secs mod 3600) \ 60
    if h > 0 then return h.ToStr() + "h " + mins.ToStr() + "m"
    return mins.ToStr() + "m"
End Function
